defmodule GenServerIo.Anagrams.Server do
  @moduledoc """
  GenServer that manages a single anagrams game session.
  """
  use GenServer
  require Logger

  alias GenServerIo.Anagrams.{State, WordLists, WordValidator}
  alias Phoenix.PubSub

  @cleanup_interval :timer.minutes(5)
  @player_disconnect_timeout :timer.minutes(10)
  @session_inactivity_timeout :timer.hours(1)

  # Client API

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  @doc """
  Creates a new session with the given configuration.
  """
  def create_session(session_id, config \\ []) do
    DynamicSupervisor.start_child(
      GenServerIo.Anagrams.Supervisor,
      {__MODULE__, [session_id: session_id] ++ config}
    )
  end

  @doc """
  Gets the current state of the session.
  """
  def get_state(session_id) do
    GenServer.call(via_tuple(session_id), :get_state)
  end

  @doc """
  Joins a player to the session.
  """
  def join_session(session_id, user_id, nickname) do
    GenServer.call(via_tuple(session_id), {:join, user_id, nickname})
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
    GenServer.cast(via_tuple(session_id), {:mark_disconnected, user_id})
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
  Submits a word for the current round.
  """
  def submit_word(session_id, user_id, word) do
    GenServer.call(via_tuple(session_id), {:submit_word, user_id, word})
  end

  @doc """
  Removes a word from player's submissions.
  """
  def remove_word(session_id, user_id, word) do
    GenServer.call(via_tuple(session_id), {:remove_word, user_id, word})
  end

  @doc """
  Scores a word in round_end phase.
  """
  def score_word(session_id, user_id, word, score) do
    GenServer.call(via_tuple(session_id), {:score_word, user_id, word, score})
  end

  @doc """
  Advances to the next round.
  """
  def next_round(session_id) do
    GenServer.call(via_tuple(session_id), :next_round)
  end

  @doc """
  Starts a new game (from game over state).
  """
  def new_game(session_id) do
    GenServer.call(via_tuple(session_id), :new_game)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    state = State.new(session_id, opts)

    cleanup_ref = schedule_cleanup()
    state = %{state | cleanup_timer_ref: cleanup_ref}

    Logger.info("Started game session: #{session_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:join, user_id, nickname}, _from, state) do
    state =
      if Map.has_key?(state.players, user_id) do
        # Reconnecting player
        player = state.players[user_id]
        updated_player = %{player | connected: true, disconnected_at: nil}
        state = put_in(state.players[user_id], updated_player)
        State.touch_activity(state)
      else
        # Check nickname uniqueness
        if nickname_taken?(state, nickname) do
          state
        else
          # New player
          player = %{
            nickname: nickname,
            ready: false,
            connected: true,
            disconnected_at: nil,
            score: 0,
            current_round_words: []
          }

          state = put_in(state.players[user_id], player)
          state = State.touch_activity(state)
          broadcast_state_update(state)
          state
        end
      end

    result =
      if Map.has_key?(state.players, user_id) do
        {:ok, state}
      else
        {:error, :nickname_taken}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:mark_connected, user_id}, _from, state) do
    state =
      if Map.has_key?(state.players, user_id) do
        player = state.players[user_id]
        updated_player = %{player | connected: true, disconnected_at: nil}
        state = put_in(state.players[user_id], updated_player)
        state = State.touch_activity(state)
        broadcast_state_update(state)
        state
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_ready, user_id, ready}, _from, state) do
    state =
      if Map.has_key?(state.players, user_id) and state.phase == :lobby do
        player = state.players[user_id]
        updated_player = %{player | ready: ready}
        state = put_in(state.players[user_id], updated_player)
        state = State.touch_activity(state)
        broadcast_state_update(state)
        state
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    state =
      if can_start_game?(state) do
        start_round(state)
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:submit_word, user_id, word}, _from, state) do
    result =
      if state.phase == :playing and Map.has_key?(state.players, user_id) do
        word = String.upcase(word)
        player = state.players[user_id]

        cond do
          word in player.current_round_words ->
            {:error, :already_submitted}

          not WordValidator.valid_word?(word, state.current_base_word) ->
            {:error, :invalid_word}

          true ->
            updated_player = %{player | current_round_words: [word | player.current_round_words]}
            state = put_in(state.players[user_id], updated_player)
            state = State.touch_activity(state)
            broadcast_state_update(state)
            {:ok, state}
        end
      else
        {:error, :invalid_phase}
      end

    case result do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_word, user_id, word}, _from, state) do
    state =
      if state.phase == :playing and Map.has_key?(state.players, user_id) do
        word = String.upcase(word)
        player = state.players[user_id]
        updated_words = List.delete(player.current_round_words, word)
        updated_player = %{player | current_round_words: updated_words}
        state = put_in(state.players[user_id], updated_player)
        state = State.touch_activity(state)
        broadcast_state_update(state)
        state
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:score_word, user_id, word, score}, _from, state) do
    state =
      if state.phase == :round_end and Map.has_key?(state.players, user_id) and
           Map.has_key?(state.all_submissions, word) do
        # Store score for this word (shared across all players)
        state = put_in(state.votes[word], score)
        state = State.touch_activity(state)
        broadcast_state_update(state)
        state
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:next_round, _from, state) do
    state =
      if state.phase == :round_end do
        # Calculate final scores based on word scores
        state = calculate_and_apply_scores(state)

        # Check for winner
        winner_id =
          Enum.find_value(state.players, fn {id, player} ->
            if player.score >= state.target_score, do: id, else: nil
          end)

        # Either go to game_over or start next round
        if winner_id do
          state = %{state | phase: :game_over, winner_id: winner_id}
          state = State.touch_activity(state)
          broadcast_state_update(state)
          state
        else
          start_round(state)
        end
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:new_game, _from, state) do
    state =
      if state.phase == :game_over do
        reset_game(state)
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:mark_disconnected, user_id}, state) do
    state =
      if Map.has_key?(state.players, user_id) do
        player = state.players[user_id]
        updated_player = %{player | connected: false, disconnected_at: DateTime.utc_now()}
        state = put_in(state.players[user_id], updated_player)
        broadcast_state_update(state)
        state
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:round_timer_expired, state) do
    state =
      if state.phase == :playing do
        end_round(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:timer_update, state) do
    state =
      if state.phase == :playing and state.time_remaining > 0 do
        new_time = state.time_remaining - 1
        state = %{state | time_remaining: new_time}

        # Continue scheduling updates if time remains
        if new_time > 0 do
          schedule_timer_update()
        end

        broadcast_state_update(state)
        state
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = cleanup_disconnected_players(state)
    state = check_session_inactivity(state)
    cleanup_ref = schedule_cleanup()
    state = %{state | cleanup_timer_ref: cleanup_ref}
    {:noreply, state}
  end

  # Private Functions

  defp via_tuple(session_id) do
    {:via, Registry, {GenServerIo.Anagrams.Registry, session_id}}
  end

  defp nickname_taken?(state, nickname) do
    Enum.any?(state.players, fn {_id, player} ->
      String.downcase(player.nickname) == String.downcase(nickname)
    end)
  end

  defp can_start_game?(state) do
    state.phase == :lobby and
      map_size(state.players) > 0 and
      all_players_ready?(state)
  end

  defp all_players_ready?(state) do
    Enum.all?(state.players, fn {_id, player} ->
      player.connected and player.ready
    end)
  end

  defp start_round(state) do
    # Generate new base word, excluding already used words
    base_word =
      WordLists.random_word(state.language, state.word_length_category, state.used_words)

    # Check if all words were used and we need to reset
    all_words = WordLists.get_word_list(state.language, state.word_length_category)

    used_words =
      if MapSet.size(state.used_words) >= length(all_words) do
        MapSet.new([base_word])
      else
        MapSet.put(state.used_words, base_word)
      end

    # Clear player submissions and set not ready
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | current_round_words: [], ready: false}}
      end)

    # Start timer for round expiration
    duration_seconds = state.round_duration * 60
    duration_ms = duration_seconds * 1000
    timer_ref = Process.send_after(self(), :round_timer_expired, duration_ms)

    # Schedule first timer update (1 second from now)
    schedule_timer_update()

    state = %{
      state
      | phase: :playing,
        current_base_word: base_word,
        round_number: state.round_number + 1,
        round_start_time: DateTime.utc_now(),
        timer_ref: timer_ref,
        time_remaining: duration_seconds,
        players: players,
        all_submissions: %{},
        votes: %{},
        validated_words: %{},
        game_ever_started: true,
        used_words: used_words
    }

    state = State.touch_activity(state)
    broadcast_state_update(state)
    state
  end

  defp end_round(state) do
    # Cancel timer if exists
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Collect all submissions
    all_submissions =
      Enum.reduce(state.players, %{}, fn {user_id, player}, acc ->
        Enum.reduce(player.current_round_words, acc, fn word, word_acc ->
          Map.update(word_acc, word, [user_id], fn submitters -> [user_id | submitters] end)
        end)
      end)

    # Initialize votes for all words with default score of 1
    votes =
      Map.new(all_submissions, fn {word, _submitters} ->
        {word, 1}
      end)

    state = %{
      state
      | phase: :round_end,
        all_submissions: all_submissions,
        votes: votes,
        timer_ref: nil
    }

    state = State.touch_activity(state)
    broadcast_state_update(state)
    state
  end

  defp calculate_and_apply_scores(state) do
    # Get scores for each word (shared vote, not per-player)
    word_scores =
      Map.new(state.votes, fn {word, score} ->
        {word, score}
      end)

    # Track which words have been scored to detect duplicates
    scored_words = MapSet.new()

    # Update player scores based on word scores
    players =
      Enum.reduce(state.all_submissions, state.players, fn {word, submitters}, acc_players ->
        word_score = Map.get(word_scores, word, 1)
        is_duplicate = MapSet.member?(scored_words, word)

        # Only first submitter gets points
        first_submitter = List.first(Enum.reverse(submitters))

        if first_submitter != nil && !is_duplicate do
          player = acc_players[first_submitter]
          # Use the vote score directly: +1, 0, or -1
          score_delta = word_score

          updated_player = %{player | score: player.score + score_delta}
          Map.put(acc_players, first_submitter, updated_player)
        else
          acc_players
        end
      end)

    # Update validated_words based on scores
    validated_words =
      Map.new(word_scores, fn {word, score} ->
        {word, score > 0}
      end)

    %{state | players: players, validated_words: validated_words}
  end

  defp reset_game(state) do
    # Reset all player scores but keep players
    players =
      Map.new(state.players, fn {id, player} ->
        {id,
         %{
           player
           | score: 0,
             ready: false,
             current_round_words: []
         }}
      end)

    state = %{
      state
      | phase: :lobby,
        players: players,
        current_base_word: nil,
        round_number: 0,
        round_start_time: nil,
        timer_ref: nil,
        time_remaining: nil,
        all_submissions: %{},
        votes: %{},
        validated_words: %{},
        winner_id: nil,
        used_words: MapSet.new()
    }

    state = State.touch_activity(state)
    broadcast_state_update(state)
    state
  end

  defp cleanup_disconnected_players(state) do
    now = DateTime.utc_now()

    players =
      state.players
      |> Enum.reject(fn {_id, player} ->
        player.disconnected_at != nil and
          DateTime.diff(now, player.disconnected_at, :millisecond) > @player_disconnect_timeout
      end)
      |> Map.new()

    if map_size(players) != map_size(state.players) do
      state = %{state | players: players}
      broadcast_state_update(state)
      state
    else
      state
    end
  end

  defp check_session_inactivity(state) do
    now = DateTime.utc_now()
    inactive_time = DateTime.diff(now, state.last_activity, :millisecond)

    if inactive_time > @session_inactivity_timeout do
      Logger.info("Terminating inactive session: #{state.session_id}")
      {:stop, :normal, state}
    else
      state
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp schedule_timer_update do
    Process.send_after(self(), :timer_update, 1000)
  end

  defp broadcast_state_update(state) do
    PubSub.broadcast(
      GenServerIo.PubSub,
      "session:#{state.session_id}",
      {:state_updated, state}
    )
  end
end
