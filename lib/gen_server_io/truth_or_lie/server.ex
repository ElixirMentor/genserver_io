defmodule GenServerIo.TruthOrLie.Server do
  @moduledoc """
  GenServer managing the state for a single Truth or Lie game session.

  Each session runs as an independent supervised process, handling:
  - Player connections and reconnections
  - Game phase transitions (lobby -> creating -> guessing -> results -> round_end -> game_over)
  - Timer management for creation and guessing phases
  - Score calculation and tracking
  - Session cleanup after inactivity
  """

  use GenServer
  require Logger

  alias GenServerIo.TruthOrLie.State

  # Client API

  @doc """
  Starts a new game session with the given session_id and target_score.
  """
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    target_score = Keyword.get(opts, :target_score, 15)

    GenServer.start_link(__MODULE__, {session_id, target_score}, name: via_tuple(session_id))
  end

  @doc """
  Returns a tuple for Registry-based process lookup.
  """
  def via_tuple(session_id) do
    {:via, Registry, {GenServerIo.TruthOrLie.Registry, session_id}}
  end

  @doc """
  Joins a player to the session with the given user_id and nickname.
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
  Sets the ready state for a player.
  """
  def set_ready(session_id, user_id, ready) do
    GenServer.call(via_tuple(session_id), {:set_ready, user_id, ready})
  end

  @doc """
  Starts the game (transitions from lobby to creating phase).
  """
  def start_game(session_id) do
    GenServer.call(via_tuple(session_id), :start_game)
  end

  @doc """
  Submits a question during the creating phase.
  """
  def submit_question(session_id, user_id, question_data) do
    GenServer.call(via_tuple(session_id), {:submit_question, user_id, question_data})
  end

  @doc """
  Submits a guess during the guessing phase.
  """
  def submit_guess(session_id, user_id, guess) do
    GenServer.call(via_tuple(session_id), {:submit_guess, user_id, guess})
  end

  @doc """
  Continues to the next question or round end.
  """
  def continue(session_id) do
    GenServer.call(via_tuple(session_id), :continue)
  end

  @doc """
  Starts a new round (from round_end back to lobby).
  """
  def next_round(session_id) do
    GenServer.call(via_tuple(session_id), :next_round)
  end

  @doc """
  Starts a new game (from game_over back to lobby with reset scores).
  """
  def new_game(session_id) do
    GenServer.call(via_tuple(session_id), :new_game)
  end

  @doc """
  Gets the current game state.
  """
  def get_state(session_id) do
    GenServer.call(via_tuple(session_id), :get_state)
  end

  @doc """
  Marks a player as disconnected.
  """
  def leave_session(session_id, user_id) do
    GenServer.cast(via_tuple(session_id), {:leave_session, user_id})
  end

  # Server Callbacks

  @impl true
  def init({session_id, target_score}) do
    state = State.new(session_id, target_score)

    # Schedule cleanup check
    Process.send_after(self(), :check_cleanup, :timer.minutes(5))

    {:ok, state}
  end

  @impl true
  def handle_call({:join_session, user_id, nickname}, _from, state) do
    case State.join_player(state, user_id, nickname) do
      {:ok, new_state} ->
        broadcast_state_update(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:mark_connected, user_id}, _from, state) do
    new_state = State.mark_player_connected(state, user_id)
    broadcast_state_update(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:set_ready, user_id, ready}, _from, state) do
    new_state = State.set_player_ready(state, user_id, ready)

    # Check if we should auto-advance
    new_state = maybe_auto_advance(new_state)

    # Broadcast state update AFTER auto-advance
    broadcast_state_update(new_state)

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    case State.start_game(state) do
      {:ok, new_state} ->
        new_state = start_creation_timer(new_state)
        broadcast_state_update(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:submit_question, user_id, question_data}, _from, state) do
    new_state = State.submit_question(state, user_id, question_data)

    # Check if all players are ready and auto-advance if needed
    new_state = maybe_auto_advance(new_state)

    # Broadcast state update AFTER auto-advance
    broadcast_state_update(new_state)

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:submit_guess, user_id, guess}, _from, state) do
    new_state = State.submit_guess(state, user_id, guess)

    # Check if all guessers are ready and auto-advance if needed
    new_state = maybe_auto_advance(new_state)

    # Broadcast state update AFTER auto-advance
    broadcast_state_update(new_state)

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:continue, _from, state) do
    new_state = State.continue_from_results(state)
    new_state = maybe_start_guessing_timer(new_state)
    broadcast_state_update(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:next_round, _from, state) do
    new_state = State.next_round(state)
    broadcast_state_update(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:new_game, _from, state) do
    new_state = State.new_game(state)
    broadcast_state_update(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:leave_session, user_id}, state) do
    new_state = State.mark_player_disconnected(state, user_id)
    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = State.decrement_timer(state)

    if new_state.time_remaining <= 0 do
      # Timer expired, advance phase
      new_state = handle_timer_expiration(new_state)
      broadcast_state_update(new_state)
      {:noreply, new_state}
    else
      # Schedule next tick
      timer_ref = Process.send_after(self(), :tick, 1000)
      new_state = %{new_state | phase_timer_ref: timer_ref}

      # Broadcast time update
      broadcast_timer_update(new_state)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:check_cleanup, state) do
    # Remove disconnected players after 10 minutes
    new_state = State.cleanup_disconnected_players(state)

    # Check if session should be terminated (1 hour of inactivity)
    if State.should_terminate?(new_state) do
      {:stop, :normal, new_state}
    else
      # Schedule next cleanup check
      Process.send_after(self(), :check_cleanup, :timer.minutes(5))
      {:noreply, new_state}
    end
  end

  # Private Helpers

  defp maybe_auto_advance(state) do
    case state.phase do
      :creating ->
        if State.all_players_ready?(state) do
          state
          |> cancel_timer()
          |> State.advance_to_guessing()
          |> start_guessing_timer()
        else
          state
        end

      :guessing ->
        if State.all_guessers_ready?(state) do
          state
          |> cancel_timer()
          |> State.advance_to_results()
        else
          state
        end

      _ ->
        state
    end
  end

  defp handle_timer_expiration(state) do
    state = cancel_timer(state)

    case state.phase do
      :creating ->
        state
        |> State.advance_to_guessing()
        |> start_guessing_timer()

      :guessing ->
        State.advance_to_results(state)

      _ ->
        state
    end
  end

  defp start_creation_timer(state) do
    # 3 minutes for creation phase
    start_timer(state, 180)
  end

  defp start_guessing_timer(state) do
    # 1 minute for guessing phase
    start_timer(state, 60)
  end

  defp maybe_start_guessing_timer(state) do
    if state.phase == :guessing do
      start_guessing_timer(state)
    else
      state
    end
  end

  defp start_timer(state, duration_seconds) do
    # Cancel existing timer if any
    state = cancel_timer(state)

    # Start new timer with 1-second ticks
    timer_ref = Process.send_after(self(), :tick, 1000)

    %{
      state
      | phase_timer_ref: timer_ref,
        phase_start_time: DateTime.utc_now(),
        phase_duration: duration_seconds,
        time_remaining: duration_seconds
    }
  end

  defp cancel_timer(state) do
    if state.phase_timer_ref do
      Process.cancel_timer(state.phase_timer_ref)
    end

    %{state | phase_timer_ref: nil}
  end

  defp broadcast_state_update(state) do
    Phoenix.PubSub.broadcast(
      GenServerIo.PubSub,
      "session:#{state.session_id}",
      {:state_updated, state}
    )
  end

  defp broadcast_timer_update(state) do
    Phoenix.PubSub.broadcast(
      GenServerIo.PubSub,
      "session:#{state.session_id}",
      {:timer_update, state.time_remaining}
    )
  end
end
