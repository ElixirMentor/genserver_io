defmodule GenServerIo.Anagrams.WordValidator do
  @moduledoc """
  Validates words against a base word according to anagrams rules.
  """

  @doc """
  Checks if a word is valid based on the base word.

  A word is valid if:
  - All letters are from the base word
  - Each letter is used no more times than it appears in the base word

  ## Examples

      iex> GenServerIo.Anagrams.WordValidator.valid_word?("CAT", "CREATING")
      true

      iex> GenServerIo.Anagrams.WordValidator.valid_word?("ZOO", "CREATING")
      false

      iex> GenServerIo.Anagrams.WordValidator.valid_word?("AAAA", "CREATING")
      false
  """
  def valid_word?(word, base_word) do
    word = String.upcase(word)
    base = String.upcase(base_word)

    letters_available?(word, base)
  end

  @doc """
  Checks if all letters in the word are available in the base word.
  """
  def letters_available?(word, base_word) do
    word_graphemes = String.graphemes(word)
    base_graphemes = String.graphemes(base_word)

    Enum.all?(word_graphemes, fn letter ->
      count_in_word = Enum.count(word_graphemes, &(&1 == letter))
      count_in_base = Enum.count(base_graphemes, &(&1 == letter))
      count_in_word <= count_in_base
    end)
  end

  @doc """
  Calculates the score for a word.

  Scoring rules:
  - Invalid words: 0 points
  - Duplicate submissions: 0 points
  - Valid words: 1 point per letter
  - Bonus: +5 points for words with 8+ letters
  """
  def calculate_score(word, is_valid, is_duplicate) do
    cond do
      not is_valid ->
        0

      is_duplicate ->
        0

      true ->
        base_points = String.length(word)
        bonus = if String.length(word) >= 8, do: 5, else: 0
        base_points + bonus
    end
  end
end
