defmodule GenServerIo.WordleBattle.State do
  @moduledoc """
  State structure for a Wordle Battle game session.

  Tracks all game state including players, phase, timing, and word management.
  """

  @type phase :: :lobby | :playing | :game_over

  @type player :: %{
          nickname: String.t(),
          ready: boolean(),
          connected: boolean(),
          disconnected_at: DateTime.t() | nil,
          current_word: String.t() | nil,
          current_attempts: [attempt()],
          words_completed: non_neg_integer(),
          words_guessed: non_neg_integer(),
          total_attempts: non_neg_integer(),
          score: non_neg_integer(),
          word_history: [word_result()]
        }

  @type attempt :: %{
          guess: String.t(),
          result: [letter_result()]
        }

  @type letter_result :: :correct | :present | :wrong

  @type word_result :: %{
          word: String.t(),
          guessed: boolean(),
          attempts: non_neg_integer(),
          points: non_neg_integer()
        }

  @type ranking :: %{
          user_id: String.t(),
          nickname: String.t(),
          score: non_neg_integer(),
          avg_attempts: float()
        }

  @type t :: %__MODULE__{
          session_id: String.t(),
          session_duration: pos_integer(),
          language: :en | :ru,
          phase: phase(),
          players: %{String.t() => player()},
          used_words: [String.t()],
          session_start_time: DateTime.t() | nil,
          session_end_time: DateTime.t() | nil,
          timer_ref: reference() | nil,
          time_remaining: non_neg_integer() | nil,
          game_ever_started: boolean(),
          cleanup_timer_ref: reference() | nil,
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          winner_id: String.t() | nil,
          final_rankings: [ranking()]
        }

  defstruct session_id: nil,
            session_duration: 3,
            language: :en,
            phase: :lobby,
            players: %{},
            used_words: [],
            session_start_time: nil,
            session_end_time: nil,
            timer_ref: nil,
            time_remaining: nil,
            game_ever_started: false,
            cleanup_timer_ref: nil,
            created_at: nil,
            last_activity: nil,
            winner_id: nil,
            final_rankings: []

  @doc """
  Creates a new game state with the given session ID, duration, and language.

  ## Parameters

    - `session_id` - Unique identifier for the session
    - `duration` - Session duration in minutes (1, 3, or 5)
    - `language` - Language for words (:en or :ru)

  ## Examples

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state.session_id
      "abc123"

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state.session_duration
      3

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state.phase
      :lobby
  """
  def new(session_id, duration \\ 3, language \\ :en)
      when duration in [1, 3, 5] and language in [:en, :ru] do
    now = DateTime.utc_now()

    %__MODULE__{
      session_id: session_id,
      session_duration: duration,
      language: language,
      created_at: now,
      last_activity: now
    }
  end

  @doc """
  Creates a new player with default values.

  ## Parameters

    - `nickname` - Display name for the player

  ## Examples

      iex> player = GenServerIo.WordleBattle.State.new_player("Alice")
      iex> player.nickname
      "Alice"

      iex> player = GenServerIo.WordleBattle.State.new_player("Bob")
      iex> player.connected
      true

      iex> player = GenServerIo.WordleBattle.State.new_player("Charlie")
      iex> player.score
      0
  """
  def new_player(nickname) do
    %{
      nickname: nickname,
      ready: false,
      connected: true,
      disconnected_at: nil,
      current_word: nil,
      current_attempts: [],
      words_completed: 0,
      words_guessed: 0,
      total_attempts: 0,
      score: 0,
      word_history: []
    }
  end

  @doc """
  Adds a player to the game state.

  ## Parameters

    - `state` - Current game state
    - `user_id` - Unique identifier for the user
    - `nickname` - Display name for the player

  ## Examples

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state = GenServerIo.WordleBattle.State.add_player(state, "user1", "Alice")
      iex> Map.has_key?(state.players, "user1")
      true

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state = GenServerIo.WordleBattle.State.add_player(state, "user1", "Alice")
      iex> state.players["user1"].nickname
      "Alice"
  """
  def add_player(%__MODULE__{} = state, user_id, nickname) do
    player = new_player(nickname)
    now = DateTime.utc_now()

    %{state | players: Map.put(state.players, user_id, player), last_activity: now}
  end

  @doc """
  Checks if all connected players are ready.

  ## Examples

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state = GenServerIo.WordleBattle.State.add_player(state, "user1", "Alice")
      iex> GenServerIo.WordleBattle.State.all_players_ready?(state)
      false

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state = GenServerIo.WordleBattle.State.add_player(state, "user1", "Alice")
      iex> state = put_in(state.players["user1"].ready, true)
      iex> GenServerIo.WordleBattle.State.all_players_ready?(state)
      true
  """
  def all_players_ready?(%__MODULE__{players: players}) when map_size(players) == 0 do
    false
  end

  def all_players_ready?(%__MODULE__{players: players}) do
    players
    |> Enum.filter(fn {_id, player} -> player.connected end)
    |> Enum.all?(fn {_id, player} -> player.ready end)
  end

  @doc """
  Returns the count of connected players.

  ## Examples

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> GenServerIo.WordleBattle.State.connected_player_count(state)
      0

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> state = GenServerIo.WordleBattle.State.add_player(state, "user1", "Alice")
      iex> GenServerIo.WordleBattle.State.connected_player_count(state)
      1
  """
  def connected_player_count(%__MODULE__{players: players}) do
    players
    |> Enum.count(fn {_id, player} -> player.connected end)
  end

  @doc """
  Updates the last activity timestamp.

  ## Examples

      iex> state = GenServerIo.WordleBattle.State.new("abc123", 3, :en)
      iex> old_time = state.last_activity
      iex> :timer.sleep(10)
      iex> state = GenServerIo.WordleBattle.State.touch(state)
      iex> DateTime.compare(state.last_activity, old_time)
      :gt
  """
  def touch(%__MODULE__{} = state) do
    %{state | last_activity: DateTime.utc_now()}
  end
end
