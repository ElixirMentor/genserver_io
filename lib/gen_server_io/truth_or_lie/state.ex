defmodule GenServerIo.TruthOrLie.State do
  @moduledoc """
  State management and business logic for the Truth or Lie game.

  Handles:
  - Game state structure
  - Phase transitions
  - Player management
  - Scoring calculations
  - Validation logic
  """

  defstruct [
    :session_id,
    :target_score,
    :phase,
    :round_number,
    :players,
    :current_question_index,
    :player_order,
    :phase_timer_ref,
    :phase_start_time,
    :phase_duration,
    :time_remaining,
    :current_results,
    :game_ever_started,
    :created_at,
    :last_activity,
    :winner_id,
    :final_rankings
  ]

  @type phase :: :lobby | :creating | :guessing | :results | :round_end | :game_over

  @type player :: %{
          nickname: String.t(),
          ready: boolean(),
          connected: boolean(),
          disconnected_at: DateTime.t() | nil,
          question: question() | nil,
          current_guess: String.t() | nil,
          total_score: integer(),
          round_score: integer(),
          questions_created: integer(),
          correct_guesses: integer(),
          times_fooled_everyone: integer()
        }

  @type question :: %{
          text: String.t(),
          answers: [answer()]
        }

  @type answer :: %{
          label: String.t(),
          text: String.t(),
          is_truth: boolean()
        }

  @type t :: %__MODULE__{
          session_id: String.t(),
          target_score: integer(),
          phase: phase(),
          round_number: integer(),
          players: %{String.t() => player()},
          current_question_index: integer() | nil,
          player_order: [String.t()],
          phase_timer_ref: reference() | nil,
          phase_start_time: DateTime.t() | nil,
          phase_duration: integer() | nil,
          time_remaining: integer() | nil,
          current_results: map() | nil,
          game_ever_started: boolean(),
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          winner_id: String.t() | nil,
          final_rankings: [map()] | nil
        }

  # Initialization

  @doc """
  Creates a new game state.
  """
  def new(session_id, target_score \\ 15) do
    %__MODULE__{
      session_id: session_id,
      target_score: target_score,
      phase: :lobby,
      round_number: 1,
      players: %{},
      current_question_index: nil,
      player_order: [],
      phase_timer_ref: nil,
      phase_start_time: nil,
      phase_duration: nil,
      time_remaining: nil,
      current_results: nil,
      game_ever_started: false,
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      winner_id: nil,
      final_rankings: nil
    }
  end

  # Player Management

  @doc """
  Adds a player to the session.
  """
  def join_player(state, user_id, nickname) do
    state = update_activity(state)

    cond do
      Map.has_key?(state.players, user_id) ->
        # Player reconnecting
        {:ok, mark_player_connected(state, user_id)}

      nickname_taken?(state, nickname) ->
        {:error, :nickname_taken}

      true ->
        player = %{
          nickname: nickname,
          ready: false,
          connected: true,
          disconnected_at: nil,
          question: nil,
          current_guess: nil,
          total_score: 0,
          round_score: 0,
          questions_created: 0,
          correct_guesses: 0,
          times_fooled_everyone: 0
        }

        new_state = %{state | players: Map.put(state.players, user_id, player)}
        {:ok, new_state}
    end
  end

  @doc """
  Marks a player as connected.
  """
  def mark_player_connected(state, user_id) do
    state = update_activity(state)

    if Map.has_key?(state.players, user_id) do
      update_in(state.players[user_id], fn player ->
        %{player | connected: true, disconnected_at: nil}
      end)
    else
      state
    end
  end

  @doc """
  Marks a player as disconnected.
  """
  def mark_player_disconnected(state, user_id) do
    if Map.has_key?(state.players, user_id) do
      update_in(state.players[user_id], fn player ->
        %{player | connected: false, disconnected_at: DateTime.utc_now()}
      end)
    else
      state
    end
  end

  @doc """
  Sets a player's ready state.
  """
  def set_player_ready(state, user_id, ready) do
    state = update_activity(state)

    if Map.has_key?(state.players, user_id) do
      update_in(state.players[user_id], fn player ->
        %{player | ready: ready}
      end)
    else
      state
    end
  end

  # Phase Transitions

  @doc """
  Starts the game (lobby -> creating).
  """
  def start_game(state) do
    connected_players = count_connected_players(state)

    cond do
      state.phase != :lobby ->
        {:error, :not_in_lobby}

      connected_players < 2 ->
        {:error, :not_enough_players}

      not all_players_ready?(state) ->
        {:error, :not_all_ready}

      true ->
        new_state = %{
          state
          | phase: :creating,
            game_ever_started: true,
            player_order: initialize_player_order(state.players)
        }

        # Reset ready states and clear questions
        new_state = reset_players_for_creation(new_state)

        {:ok, new_state}
    end
  end

  @doc """
  Advances from creating to guessing phase.
  """
  def advance_to_guessing(state) do
    %{
      state
      | phase: :guessing,
        current_question_index: 0
    }
    |> reset_ready_states()
  end

  @doc """
  Advances from guessing to results phase.
  """
  def advance_to_results(state) do
    # Calculate scores for current question
    results = calculate_question_results(state)

    # Apply scores to players
    new_state = apply_question_scores(state, results)

    %{new_state | phase: :results, current_results: results}
  end

  @doc """
  Continues from results to either next question or round end.
  """
  def continue_from_results(state) do
    next_index = state.current_question_index + 1
    total_questions = length(state.player_order)

    if next_index < total_questions do
      # More questions remain
      %{state | current_question_index: next_index, phase: :guessing, current_results: nil}
      |> reset_guesses()
      |> reset_ready_states()
    else
      # Round complete
      advance_to_round_end(state)
    end
  end

  @doc """
  Advances to round end phase.
  """
  def advance_to_round_end(state) do
    # Check if anyone won
    winner = find_winner(state)

    if winner do
      advance_to_game_over(state, winner)
    else
      %{state | phase: :round_end, current_results: nil}
    end
  end

  @doc """
  Advances to game over phase.
  """
  def advance_to_game_over(state, winner_id) do
    rankings = calculate_final_rankings(state)

    %{
      state
      | phase: :game_over,
        winner_id: winner_id,
        final_rankings: rankings
    }
  end

  @doc """
  Starts a new round (round_end -> lobby).
  """
  def next_round(state) do
    %{
      state
      | phase: :lobby,
        round_number: state.round_number + 1,
        current_question_index: nil,
        current_results: nil
    }
    |> reset_round_scores()
    |> reset_ready_states()
    |> clear_questions()
  end

  @doc """
  Starts a new game (game_over -> lobby with full reset).
  """
  def new_game(state) do
    %{
      state
      | phase: :lobby,
        round_number: 1,
        current_question_index: nil,
        current_results: nil,
        winner_id: nil,
        final_rankings: nil
    }
    |> reset_all_scores()
    |> reset_ready_states()
    |> clear_questions()
  end

  # Question and Guess Management

  @doc """
  Submits a question for a player.
  """
  def submit_question(state, user_id, question_data) do
    state = update_activity(state)

    if Map.has_key?(state.players, user_id) and state.phase == :creating do
      question = %{
        text: question_data["text"] || "",
        answers: parse_answers(question_data["answers"] || [])
      }

      update_in(state.players[user_id], fn player ->
        %{player | question: question, ready: true}
      end)
    else
      state
    end
  end

  @doc """
  Submits a guess for a player.
  """
  def submit_guess(state, user_id, guess) do
    state = update_activity(state)

    author_id = get_current_question_author(state)

    # Only allow guesses from non-authors
    if Map.has_key?(state.players, user_id) and user_id != author_id and
         state.phase == :guessing do
      update_in(state.players[user_id], fn player ->
        %{player | current_guess: guess, ready: true}
      end)
    else
      state
    end
  end

  # Ready State Checks

  @doc """
  Checks if all connected players are ready.
  """
  def all_players_ready?(state) do
    state.players
    |> Map.values()
    |> Enum.filter(& &1.connected)
    |> Enum.all?(& &1.ready)
  end

  @doc """
  Checks if all guessers (non-authors) are ready.
  """
  def all_guessers_ready?(state) do
    author_id = get_current_question_author(state)

    state.players
    |> Enum.reject(fn {id, _} -> id == author_id end)
    |> Enum.map(fn {_, player} -> player end)
    |> Enum.filter(& &1.connected)
    |> Enum.all?(& &1.ready)
  end

  # Timer Management

  @doc """
  Decrements the timer by 1 second.
  """
  def decrement_timer(state) do
    if state.time_remaining do
      %{state | time_remaining: max(0, state.time_remaining - 1)}
    else
      state
    end
  end

  # Cleanup

  @doc """
  Removes players disconnected for more than 10 minutes.
  """
  def cleanup_disconnected_players(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -600, :second)

    players =
      state.players
      |> Enum.reject(fn {_, player} ->
        not player.connected and player.disconnected_at and
          DateTime.compare(player.disconnected_at, cutoff) == :lt
      end)
      |> Map.new()

    %{state | players: players}
  end

  @doc """
  Checks if session should be terminated (1 hour of inactivity).
  """
  def should_terminate?(state) do
    # Don't terminate if game is active
    if state.phase != :lobby or state.game_ever_started do
      false
    else
      cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
      DateTime.compare(state.last_activity, cutoff) == :lt
    end
  end

  # Helper Functions

  defp nickname_taken?(state, nickname) do
    state.players
    |> Map.values()
    |> Enum.any?(fn player -> player.nickname == nickname end)
  end

  defp count_connected_players(state) do
    state.players
    |> Map.values()
    |> Enum.count(& &1.connected)
  end

  defp initialize_player_order(players) do
    players
    |> Map.keys()
    |> Enum.sort()
  end

  defp reset_players_for_creation(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | ready: false, question: nil, round_score: 0}}
      end)

    %{state | players: players}
  end

  defp reset_ready_states(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | ready: false}}
      end)

    %{state | players: players}
  end

  defp reset_guesses(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | current_guess: nil}}
      end)

    %{state | players: players}
  end

  defp reset_round_scores(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | round_score: 0}}
      end)

    %{state | players: players}
  end

  defp reset_all_scores(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id,
         %{
           player
           | total_score: 0,
             round_score: 0,
             questions_created: 0,
             correct_guesses: 0,
             times_fooled_everyone: 0
         }}
      end)

    %{state | players: players}
  end

  defp clear_questions(state) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | question: nil, current_guess: nil}}
      end)

    %{state | players: players}
  end

  defp parse_answers(answers) when is_list(answers) do
    answers
    |> Enum.take(3)
    |> Enum.with_index()
    |> Enum.map(fn {answer, index} ->
      label = Enum.at(["A", "B", "C"], index)

      %{
        label: label,
        text: answer["text"] || "",
        is_truth: answer["is_truth"] || false
      }
    end)
  end

  defp get_current_question_author(state) do
    if state.current_question_index do
      Enum.at(state.player_order, state.current_question_index)
    else
      nil
    end
  end

  defp calculate_question_results(state) do
    author_id = get_current_question_author(state)
    author = state.players[author_id]

    # Find correct answer
    correct_answer =
      if author.question do
        author.question.answers
        |> Enum.find(fn a -> a.is_truth end)
        |> case do
          nil -> "A"
          answer -> answer.label
        end
      else
        "A"
      end

    # Collect all guesses
    player_guesses =
      state.players
      |> Enum.reject(fn {id, _} -> id == author_id end)
      |> Map.new(fn {id, player} ->
        guess = player.current_guess
        correct = guess == correct_answer

        {id, %{guess: guess, correct: correct, points_awarded: if(correct, do: 1, else: 0)}}
      end)

    # Calculate author points
    all_wrong =
      player_guesses
      |> Map.values()
      |> Enum.all?(fn g -> not g.correct end)

    author_points = if all_wrong and map_size(player_guesses) > 0, do: 2, else: 0

    %{
      question_author: author_id,
      correct_answer: correct_answer,
      player_guesses: player_guesses,
      author_points: author_points
    }
  end

  defp apply_question_scores(state, results) do
    # Apply points to guessers
    state =
      Enum.reduce(results.player_guesses, state, fn {player_id, guess_result}, acc_state ->
        if guess_result.correct do
          update_in(acc_state.players[player_id], fn player ->
            %{
              player
              | total_score: player.total_score + 1,
                round_score: player.round_score + 1,
                correct_guesses: player.correct_guesses + 1
            }
          end)
        else
          acc_state
        end
      end)

    # Apply points to author
    author_id = results.question_author

    if results.author_points > 0 do
      update_in(state.players[author_id], fn player ->
        %{
          player
          | total_score: player.total_score + results.author_points,
            round_score: player.round_score + results.author_points,
            times_fooled_everyone: player.times_fooled_everyone + 1
        }
      end)
    else
      state
    end
  end

  defp find_winner(state) do
    state.players
    |> Enum.find(fn {_, player} -> player.total_score >= state.target_score end)
    |> case do
      {user_id, _} -> user_id
      nil -> nil
    end
  end

  defp calculate_final_rankings(state) do
    state.players
    |> Enum.map(fn {user_id, player} ->
      %{
        user_id: user_id,
        nickname: player.nickname,
        total_score: player.total_score,
        questions_created: player.questions_created,
        correct_guesses: player.correct_guesses,
        times_fooled_everyone: player.times_fooled_everyone
      }
    end)
    |> Enum.sort_by(& &1.total_score, :desc)
  end

  defp update_activity(state) do
    %{state | last_activity: DateTime.utc_now()}
  end
end
