defmodule GenServerIo.WordleBattle.Server do
  @moduledoc """
  GenServer that manages a single Wordle Battle game session.

  Handles game state, player management, word assignment, guess validation,
  scoring, and real-time updates via PubSub.
  """

  use GenServer
  require Logger

  alias GenServerIo.WordleBattle.{Dictionary, State}
  alias Phoenix.PubSub

  @cleanup_interval_ms 5 * 60 * 1000
  @disconnection_grace_period_minutes 10
  @session_timeout_minutes 60

  # Client API

  @doc """
  Starts a new game session.
  """
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    duration = Keyword.get(opts, :duration, 3)
    language = Keyword.get(opts, :language, :en)

    GenServer.start_link(__MODULE__, {session_id, duration, language},
      name: via_tuple(session_id)
    )
  end

  @doc """
  Creates a new game session via the DynamicSupervisor.
  """
  def create_session(session_id, duration \\ 3, language \\ :en) do
    DynamicSupervisor.start_child(
      GenServerIo.WordleBattle.Supervisor,
      {__MODULE__, session_id: session_id, duration: duration, language: language}
    )
  end

  @doc """
  Checks if a session exists.
  """
  def session_exists?(session_id) do
    case Registry.lookup(GenServerIo.WordleBattle.Registry, session_id) do
      [] -> false
      _ -> true
    end
  end

  defp via_tuple(session_id) do
    {:via, Registry, {GenServerIo.WordleBattle.Registry, session_id}}
  end

  @doc """
  Gets the current game state.
  """
  def get_state(session_id) do
    try do
      GenServer.call(via_tuple(session_id), :get_state)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  @doc """
  Joins a session with a nickname.
  """
  def join_session(session_id, user_id, nickname) do
    GenServer.call(via_tuple(session_id), {:join_session, user_id, nickname})
  end

  @doc """
  Marks a player as connected (for reconnection).
  """
  def mark_connected(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:mark_connected, user_id})
  end

  @doc """
  Marks a player as disconnected.
  """
  def mark_disconnected(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:mark_disconnected, user_id})
  end

  @doc """
  Sets a player's ready status.
  """
  def set_ready(session_id, user_id, ready) do
    GenServer.call(via_tuple(session_id), {:set_ready, user_id, ready})
  end

  @doc """
  Starts the game.
  """
  def start_game(session_id) do
    GenServer.call(via_tuple(session_id), :start_game)
  end

  @doc """
  Submits a guess for a player.
  """
  def submit_guess(session_id, user_id, guess) do
    GenServer.call(via_tuple(session_id), {:submit_guess, user_id, guess})
  end

  @doc """
  Starts a new game (resets to lobby).
  """
  def new_game(session_id) do
    GenServer.call(via_tuple(session_id), :new_game)
  end

  # Server Callbacks

  @impl true
  def init({session_id, duration, language}) do
    state = State.new(session_id, duration, language)
    Logger.info("Started Wordle Battle session: #{session_id}")

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_check, @cleanup_interval_ms)

    {:ok, %{state | cleanup_timer_ref: cleanup_timer}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:join_session, user_id, nickname}, _from, state) do
    cond do
      Map.has_key?(state.players, user_id) ->
        # Player already exists, mark as connected
        state = mark_player_connected(state, user_id)
        broadcast_state_update(state)
        {:reply, {:ok, state}, state}

      nickname_taken?(state, nickname) ->
        {:reply, {:error, :nickname_taken}, state}

      true ->
        state =
          state
          |> State.add_player(user_id, nickname)
          |> State.touch()

        broadcast_state_update(state)
        {:reply, {:ok, state}, state}
    end
  end

  @impl true
  def handle_call({:mark_connected, user_id}, _from, state) do
    if Map.has_key?(state.players, user_id) do
      state = mark_player_connected(state, user_id)
      broadcast_state_update(state)
      {:reply, {:ok, state}, state}
    else
      {:reply, {:error, :player_not_found}, state}
    end
  end

  @impl true
  def handle_call({:mark_disconnected, user_id}, _from, state) do
    if Map.has_key?(state.players, user_id) do
      players =
        state.players
        |> put_in([user_id, :connected], false)
        |> put_in([user_id, :disconnected_at], DateTime.utc_now())

      state =
        %{state | players: players}
        |> State.touch()

      broadcast_state_update(state)
      {:reply, {:ok, state}, state}
    else
      {:reply, {:error, :player_not_found}, state}
    end
  end

  @impl true
  def handle_call({:set_ready, user_id, ready}, _from, state) do
    if state.phase != :lobby do
      {:reply, {:error, :not_in_lobby}, state}
    else
      case get_in(state.players, [user_id]) do
        nil ->
          {:reply, {:error, :player_not_found}, state}

        _player ->
          players = put_in(state.players, [user_id, :ready], ready)

          state =
            %{state | players: players}
            |> State.touch()

          broadcast_state_update(state)
          {:reply, {:ok, state}, state}
      end
    end
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    cond do
      state.phase != :lobby ->
        {:reply, {:error, :not_in_lobby}, state}

      State.connected_player_count(state) == 0 ->
        {:reply, {:error, :no_players}, state}

      not State.all_players_ready?(state) ->
        {:reply, {:error, :not_all_ready}, state}

      true ->
        state = transition_to_playing(state)
        broadcast_state_update(state)
        {:reply, {:ok, state}, state}
    end
  end

  @impl true
  def handle_call({:submit_guess, user_id, guess}, _from, state) do
    cond do
      state.phase != :playing ->
        {:reply, {:error, :not_playing}, state}

      not Map.has_key?(state.players, user_id) ->
        {:reply, {:error, :player_not_found}, state}

      String.length(guess) != 5 ->
        {:reply, {:error, :invalid_length}, state}

      not Dictionary.valid_guess?(guess, state.language) ->
        {:reply, {:error, :invalid_word}, state}

      true ->
        state = process_guess(state, user_id, guess)
        broadcast_state_update(state)
        {:reply, {:ok, state}, state}
    end
  end

  @impl true
  def handle_call(:new_game, _from, state) do
    if state.phase == :game_over do
      state = reset_to_lobby(state)
      broadcast_state_update(state)
      {:reply, {:ok, state}, state}
    else
      {:reply, {:error, :not_game_over}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    time_remaining = state.time_remaining - 1

    if time_remaining <= 0 do
      state = end_game(state)
      broadcast_state_update(state)
      {:noreply, state}
    else
      state = %{state | time_remaining: time_remaining}
      broadcast_time_update(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_check, state) do
    state = perform_cleanup(state)

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_check, @cleanup_interval_ms)

    {:noreply, %{state | cleanup_timer_ref: cleanup_timer}}
  end

  # Private Functions

  defp nickname_taken?(state, nickname) do
    state.players
    |> Enum.any?(fn {_id, player} -> player.nickname == nickname end)
  end

  defp mark_player_connected(state, user_id) do
    players =
      state.players
      |> put_in([user_id, :connected], true)
      |> put_in([user_id, :disconnected_at], nil)

    %{state | players: players}
    |> State.touch()
  end

  defp transition_to_playing(state) do
    duration_seconds = state.session_duration * 60
    start_time = DateTime.utc_now()
    end_time = DateTime.add(start_time, duration_seconds, :second)

    # Pick the first word for all players
    first_word = Dictionary.random_word(state.language, state.used_words)

    # Assign the same word to all connected players
    players =
      Enum.reduce(state.players, state.players, fn {user_id, player}, acc_players ->
        if player.connected do
          acc_players
          |> put_in([user_id, :current_word], first_word)
          |> put_in([user_id, :current_attempts], [])
        else
          acc_players
        end
      end)

    state = %{state | players: players, used_words: [first_word | state.used_words]}

    # Start timer
    {:ok, timer_ref} = :timer.send_interval(1000, self(), :tick)

    %{
      state
      | phase: :playing,
        session_start_time: start_time,
        session_end_time: end_time,
        time_remaining: duration_seconds,
        timer_ref: timer_ref,
        game_ever_started: true
    }
    |> State.touch()
  end

  defp assign_new_word(state, user_id) do
    player = state.players[user_id]
    word_index = player.words_completed

    # Get the word at this index, or generate a new one if it doesn't exist
    {new_word, updated_used_words} =
      case Enum.at(state.used_words, word_index) do
        nil ->
          # Generate new word and add to sequence
          word = Dictionary.random_word(state.language, state.used_words)
          {word, state.used_words ++ [word]}

        existing_word ->
          # Use existing word from sequence
          {existing_word, state.used_words}
      end

    players =
      state.players
      |> put_in([user_id, :current_word], new_word)
      |> put_in([user_id, :current_attempts], [])

    %{state | players: players, used_words: updated_used_words}
  end

  defp process_guess(state, user_id, guess) do
    player = state.players[user_id]
    target_word = player.current_word
    normalized_guess = String.upcase(guess)

    result = check_guess(normalized_guess, target_word)
    attempt = %{guess: normalized_guess, result: result}

    players = update_in(state.players, [user_id, :current_attempts], &(&1 ++ [attempt]))
    state = %{state | players: players}

    if word_guessed?(result) do
      handle_word_completed(state, user_id, true)
    else
      attempts_count = length(state.players[user_id].current_attempts)

      if attempts_count >= 6 do
        handle_word_completed(state, user_id, false)
      else
        State.touch(state)
      end
    end
  end

  defp check_guess(guess, target) do
    guess_letters = String.graphemes(guess)
    target_letters = String.graphemes(target)

    # First pass: mark exact matches
    exact_matches =
      Enum.zip(guess_letters, target_letters)
      |> Enum.map(fn {g, t} -> if g == t, do: :correct, else: nil end)

    # Second pass: mark present letters (avoiding double-counting)
    target_remaining =
      target_letters
      |> Enum.zip(exact_matches)
      |> Enum.reject(fn {_, match} -> match == :correct end)
      |> Enum.map(fn {letter, _} -> letter end)

    {result, _} =
      Enum.zip(guess_letters, exact_matches)
      |> Enum.map_reduce(target_remaining, fn {g, match}, remaining ->
        case match do
          :correct ->
            {:correct, remaining}

          nil ->
            if g in remaining do
              {:present, List.delete(remaining, g)}
            else
              {:wrong, remaining}
            end
        end
      end)

    result
  end

  defp word_guessed?(result) do
    Enum.all?(result, &(&1 == :correct))
  end

  defp handle_word_completed(state, user_id, guessed) do
    player = state.players[user_id]
    attempts = length(player.current_attempts)
    points = calculate_score(attempts, guessed)

    word_result = %{
      word: player.current_word,
      guessed: guessed,
      attempts: attempts,
      points: points
    }

    players =
      state.players
      |> update_in([user_id, :score], &(&1 + points))
      |> update_in([user_id, :words_completed], &(&1 + 1))
      |> update_in([user_id, :total_attempts], &(&1 + attempts))
      |> update_in([user_id, :word_history], &(&1 ++ [word_result]))

    players =
      if guessed do
        update_in(players, [user_id, :words_guessed], &(&1 + 1))
      else
        players
      end

    state = %{state | players: players}

    # Assign new word
    assign_new_word(state, user_id)
  end

  defp calculate_score(attempts, true = _guessed) do
    case attempts do
      1 -> 6
      2 -> 4
      3 -> 3
      _ -> 2
    end
  end

  defp calculate_score(_attempts, false = _guessed), do: 0

  defp end_game(state) do
    # Cancel timer
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
    end

    # Calculate rankings
    rankings = calculate_rankings(state)
    winner_id = if rankings != [], do: hd(rankings).user_id, else: nil

    %{
      state
      | phase: :game_over,
        timer_ref: nil,
        time_remaining: 0,
        final_rankings: rankings,
        winner_id: winner_id
    }
    |> State.touch()
  end

  defp calculate_rankings(state) do
    state.players
    |> Enum.map(fn {user_id, player} ->
      avg_attempts =
        if player.words_guessed > 0 do
          player.total_attempts / player.words_guessed
        else
          player.total_attempts
        end

      %{
        user_id: user_id,
        nickname: player.nickname,
        score: player.score,
        avg_attempts: avg_attempts
      }
    end)
    |> Enum.sort_by(fn player -> {-player.score, player.avg_attempts} end)
  end

  defp reset_to_lobby(state) do
    # Reset all players
    players =
      Enum.into(state.players, %{}, fn {user_id, player} ->
        {user_id,
         %{
           player
           | ready: false,
             current_word: nil,
             current_attempts: [],
             words_completed: 0,
             words_guessed: 0,
             total_attempts: 0,
             score: 0,
             word_history: []
         }}
      end)

    %{
      state
      | phase: :lobby,
        players: players,
        used_words: [],
        session_start_time: nil,
        session_end_time: nil,
        timer_ref: nil,
        time_remaining: nil,
        winner_id: nil,
        final_rankings: []
    }
    |> State.touch()
  end

  defp perform_cleanup(state) do
    now = DateTime.utc_now()

    # Remove players disconnected for more than grace period
    updated_players =
      Enum.reject(state.players, fn {_id, player} ->
        player.disconnected_at != nil and
          DateTime.diff(now, player.disconnected_at, :minute) >
            @disconnection_grace_period_minutes
      end)
      |> Enum.into(%{})

    # Check if session is inactive and should be terminated
    session_inactive_minutes = DateTime.diff(now, state.last_activity, :minute)

    if session_inactive_minutes > @session_timeout_minutes and not state.game_ever_started do
      Logger.info("Terminating inactive session #{state.session_id}")
      {:stop, :normal, state}
    else
      %{state | players: updated_players}
    end
  end

  defp broadcast_state_update(state) do
    PubSub.broadcast(
      GenServerIo.PubSub,
      "game:#{state.session_id}",
      {:game_update, state}
    )
  end

  defp broadcast_time_update(state) do
    PubSub.broadcast(
      GenServerIo.PubSub,
      "game:#{state.session_id}",
      {:time_update, state.time_remaining}
    )
  end
end
