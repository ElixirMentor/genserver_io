defmodule GenServerIo.Anagrams.State do
  @moduledoc """
  Game state structure for an anagrams session.
  """

  defstruct [
    :session_id,
    :language,
    :word_length_category,
    :round_duration,
    :min_word_length,
    :target_score,
    :phase,
    :players,
    :current_base_word,
    :round_number,
    :round_start_time,
    :timer_ref,
    :time_remaining,
    :all_submissions,
    :votes,
    :validated_words,
    :game_ever_started,
    :cleanup_timer_ref,
    :created_at,
    :last_activity,
    :winner_id,
    :used_words
  ]

  @type language :: :en | :ru
  @type word_length_category :: :short | :medium | :long
  @type phase :: :lobby | :playing | :round_end | :game_over
  @type user_id :: String.t()

  @type player :: %{
          nickname: String.t(),
          ready: boolean(),
          connected: boolean(),
          disconnected_at: DateTime.t() | nil,
          score: integer(),
          current_round_words: [String.t()]
        }

  @type t :: %__MODULE__{
          session_id: String.t(),
          language: language(),
          word_length_category: word_length_category(),
          round_duration: integer(),
          min_word_length: integer(),
          target_score: integer(),
          phase: phase(),
          players: %{user_id() => player()},
          current_base_word: String.t() | nil,
          round_number: integer(),
          round_start_time: DateTime.t() | nil,
          timer_ref: reference() | nil,
          time_remaining: integer() | nil,
          all_submissions: %{String.t() => [user_id()]},
          votes: %{String.t() => integer()},
          validated_words: %{String.t() => boolean()},
          game_ever_started: boolean(),
          cleanup_timer_ref: reference() | nil,
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          winner_id: user_id() | nil,
          used_words: MapSet.t(String.t())
        }

  @doc """
  Creates a new game state with the given configuration.
  """
  def new(session_id, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      session_id: session_id,
      language: Keyword.get(opts, :language, :en),
      word_length_category: Keyword.get(opts, :word_length_category, :medium),
      round_duration: Keyword.get(opts, :round_duration, 5),
      min_word_length: Keyword.get(opts, :min_word_length, 3),
      target_score: Keyword.get(opts, :target_score, 50),
      phase: :lobby,
      players: %{},
      current_base_word: nil,
      round_number: 0,
      round_start_time: nil,
      timer_ref: nil,
      time_remaining: nil,
      all_submissions: %{},
      votes: %{},
      validated_words: %{},
      game_ever_started: false,
      cleanup_timer_ref: nil,
      created_at: now,
      last_activity: now,
      winner_id: nil,
      used_words: MapSet.new()
    }
  end

  @doc """
  Updates the last activity timestamp.
  """
  def touch_activity(%__MODULE__{} = state) do
    %{state | last_activity: DateTime.utc_now()}
  end
end
