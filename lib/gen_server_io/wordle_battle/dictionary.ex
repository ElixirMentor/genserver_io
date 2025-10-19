defmodule GenServerIo.WordleBattle.Dictionary do
  @moduledoc """
  Dictionary module for Wordle Battle game.

  Provides word lists for answers and validation of guesses in multiple languages.
  Words are embedded in the module for easy access and testing.
  """

  @answer_words_en ~w[
    ABOUT ABOVE ABUSE ACTOR ACUTE ADMIT ADOPT ADULT AFTER AGAIN
    AGENT AGREE AHEAD ALARM ALBUM ALERT ALIEN ALIGN ALIKE ALIVE
    ALLOW ALONE ALONG ALTER AMBER AMEND AMONG ANGEL ANGER ANGLE
    ANGRY APART APPLE APPLY ARENA ARGUE ARISE ARRAY ARROW ASIDE
    ASSET AUDIO AVOID AWAKE AWARD AWARE BADLY BAKER BASES BASIC
    BASIS BEACH BEGAN BEGIN BEING BELOW BENCH BILLY BIRTH BLACK
    BLAME BLAND BLANK BLEED BLEND BLESS BLIND BLOCK BLOOD BLOOM
    BOARD BOOST BOOTH BOUND BRAIN BRAND BRAVE BREAD BREAK BREED
    BRIEF BRING BROAD BROKE BROWN BUILD BUILT BUYER CABLE CALIF
    CAMEL CANAL CANDY CANOE CANON CARGO CAROL CARRY CARVE CATCH
    CAUSE CHAIN CHAIR CHALK CHAMP CHANT CHAOS CHARD CHARM CHART
    CHASE CHEAP CHEAT CHECK CHEEK CHEER CHESS CHEST CHIEF CHILD
    CHINA CHOSE CHUCK CHUNK CHURN CLAIM CLASS CLEAN CLEAR CLICK
    CLIFF CLIMB CLOAK CLOCK CLONE CLOSE CLOTH CLOUD CLOWN COAST
    COULD COUNT COUCH COUGH COURT COVER CRACK CRAFT CRASH CRAZY
    CREAM CREEK CREEP CREST CRIME CRISP CROOK CROSS CROWD CROWN
    CRUDE CRUEL CRUSH CURVE CYCLE DAILY DANCE DATED DEALT DEATH
    DEBUT DELAY DELTA DENSE DEPOT DEPTH DERBY DETER DEVIL DIARY
    DIGIT DIMLY DIRTY DISCO DITCH DIVER DIZZY DODGE DOING DONOR
    DOUBT DOUGH DOVER DRAFT DRAIN DRAMA DRANK DRAPE DRAWL DRAWN
  ]

  # Russian 5-letter words (Cyrillic)
  @answer_words_ru ~w[
    БАГАЖ БАЛКА БАНДА БАНКА БАРАК БАРОН БАТОН БАШНЯ БЕГУН БЕЛКА
    БЕРЕГ БИТВА БЛЕСК БЛЮДО БОМБА БОРЕЦ БОРЩА БОТВА БРАТЬ БРЮКИ
    БУКВА БУЛКА БУМАГА БУТОН ВАГОН ВАННА ВАРКА ВЕДРО ВЕЛИК ВЕНИК
    ВЕНОК ВЕРБА ВЕСЛО ВЕСНА ВЕТЕР ВЕТКА ВЕЧЕР ВЗГЛЯД ВИЗИТ ВИЛКА
    ВИСКИ ВИШНЯ ВЛАСТ ВЛАГА ВНУКА ВОЙНА ВОЛНА ВОРОН ВРЕМЯ ВЫБОР
    ВЫВОД ВЫСОТ ВЯЗКА ГАЗОН ГАЛКА ГАРАЖ ГЛАЗА ГЛИНА ГЛУПО ГОЛОД
    ГОЛОС ГОРОД ГОРОХ ГОСТЬ ГРАНЬ ГРИВА ГРИЛЬ ГРУША ГУБКА ДАВКА
    ДАЧКА ДЕВИЗ ДЕКОР ДЕЛЕЦ ДЕМОН ДЕНЕК ДЕСНА ДЕТКА ДИВАН ДИЕТА
    ДОСКА ДРАКА ДРОВА ДРУЖБА ДУБОК ДЫХАН ЕЖИКИ ЕЗДОК ЗАБОР ЗАВОД
    ЗАГАР ЗАДАЧ ЗАКАТ ЗАМОК ЗАПАД ЗАПАХ ЗЕБРА ЗЕЛЕН ЗЕМЛЯ ЗЕРНО
  ]

  @valid_guesses_en MapSet.new(@answer_words_en)
  @valid_guesses_ru MapSet.new(@answer_words_ru)

  @doc """
  Returns the list of valid answer words for the given language.

  These are common 5-letter words that can be assigned to players.

  ## Parameters

    - `language` - Language code (:en or :ru)

  ## Examples

      iex> GenServerIo.WordleBattle.Dictionary.answer_words(:en) |> length()
      200

      iex> GenServerIo.WordleBattle.Dictionary.answer_words(:en) |> List.first()
      "ABOUT"

      iex> GenServerIo.WordleBattle.Dictionary.answer_words(:ru) |> length()
      100
  """
  def answer_words(:en), do: @answer_words_en
  def answer_words(:ru), do: @answer_words_ru
  def answer_words(_), do: @answer_words_en

  @doc """
  Returns a MapSet of valid guesses for the given language.

  For now, this is the same as answer words, but could be expanded
  to include more obscure valid 5-letter words.

  ## Parameters

    - `language` - Language code (:en or :ru)

  ## Examples

      iex> GenServerIo.WordleBattle.Dictionary.valid_guesses(:en) |> MapSet.size()
      200

      iex> GenServerIo.WordleBattle.Dictionary.valid_guesses(:ru) |> MapSet.size()
      100
  """
  def valid_guesses(:en), do: @valid_guesses_en
  def valid_guesses(:ru), do: @valid_guesses_ru
  def valid_guesses(_), do: @valid_guesses_en

  @doc """
  Returns a random word from the answer list, optionally excluding certain words.

  ## Parameters

    - `language` - Language code (:en or :ru)
    - `exclude_list` - List of words to exclude from selection (default: [])

  ## Examples

      iex> word = GenServerIo.WordleBattle.Dictionary.random_word(:en)
      iex> String.length(word)
      5

      iex> word = GenServerIo.WordleBattle.Dictionary.random_word(:en, ["ABOUT", "ABOVE"])
      iex> word not in ["ABOUT", "ABOVE"]
      true
  """
  def random_word(language, exclude_list \\ []) do
    all_words = answer_words(language)
    available_words = all_words -- exclude_list

    case available_words do
      [] ->
        # All words used, start over with full list
        Enum.random(all_words)

      words ->
        Enum.random(words)
    end
  end

  @doc """
  Checks if a word is a valid guess for the given language.

  ## Parameters

    - `word` - The word to validate (case insensitive)
    - `language` - Language code (:en or :ru)

  ## Examples

      iex> GenServerIo.WordleBattle.Dictionary.valid_guess?("ABOUT", :en)
      true

      iex> GenServerIo.WordleBattle.Dictionary.valid_guess?("about", :en)
      true

      iex> GenServerIo.WordleBattle.Dictionary.valid_guess?("ZZZZZ", :en)
      false

      iex> GenServerIo.WordleBattle.Dictionary.valid_guess?("HI", :en)
      false

      iex> GenServerIo.WordleBattle.Dictionary.valid_guess?("БАГАЖ", :ru)
      true
  """
  def valid_guess?(word, language) when is_binary(word) do
    normalized = String.upcase(word)
    guesses = valid_guesses(language)
    String.length(normalized) == 5 and MapSet.member?(guesses, normalized)
  end

  def valid_guess?(_, _), do: false
end
