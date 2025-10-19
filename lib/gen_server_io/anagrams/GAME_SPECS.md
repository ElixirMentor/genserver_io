# Anagrams Game Functionality Specification

## Overview
A minimalistic real-time Anagrams game (Anagrams.app) built with Phoenix LiveView, utilizing PubSub and GenServers for state management with session persistence, player reconnection, and automated cleanup.

## Core Features

### 1. Session Management
- **Create Session**: Simple button to create new game session with configurable settings
- **Unique Links**: Each session gets a unique hash-based URL (`/:session_id`)
- **Language Support**: English and Russian language options with localized UI
- **Word Selection**: Choose base word length (Short: 8-10 letters, Medium: 11-13 letters, Long: 14+ letters)
- **Round Time Limit**: Configurable round duration (3, 5, 7, 10 minutes)
- **Target Score**: Configurable winning score (30, 50, 75, 100 points)
- **No Authentication**: No logins, registrations, or persistent user accounts
- **Session Persistence**: Sessions survive server restarts and player disconnections
- **Automatic Cleanup**: Sessions automatically cleaned after 1 hour of inactivity

### 2. Player Connection & Persistence
- **Unique User IDs**: Each player gets a persistent UUID stored in localStorage
- **Automatic Reconnection**: Players automatically rejoin their session on page refresh
- **Nickname Reclamation**: Disconnected players' nicknames can be reclaimed after timeout
- **Connection Status**: Players marked as connected/disconnected with timestamps
- **Graceful Degradation**: Missing players' submissions preserved; they can continue after reconnecting

### 3. Lobby System
- **Join via Link**: Users join by visiting the unique session URL
- **Nickname Entry**: Each user can set their display name (must be unique within session)
- **Individual Play**: Each player competes individually (no teams)
- **Ready State**: All connected players must press "Ready" to start game
- **Flexible Start**: Can start with 1+ players
- **Base Word Display**: Show the base word in lobby for preview (in :lobby phase only)

### 4. Game Flow
- **Round-based Gameplay**: All players submit words simultaneously during timed rounds
- **Timed Rounds**: Each round has configurable timer (3-10 minutes) with real-time countdown
- **Timer Audio**: Sound notification when time expires (`/sounds/timer_end.mp3`)
- **Base Word Display**: Current base word prominently shown during round
- **Word Submission Interface**:
  - Input field for entering words
  - Live validation showing if word is valid (correct letters/count)
  - Submit button to add word to player's list
  - Player's current word list visible during round
  - Ability to remove own words before round ends
- **Real-time Visibility**: All submissions hidden until round ends, then revealed to all
- **Auto Round End**: Round automatically ends when timer reaches zero
- **Moderation Phase**: After round, all players review all submissions collectively

### 5. Moderation & Scoring System
- **Collective Moderation**: After each round, all submitted words displayed for group review
- **Word Validation Interface**:
  - Each unique word shown with player name(s) who submitted it
  - Checkbox or toggle to mark word as valid/invalid
  - Any player can vote on any word
  - Simple majority rule: word valid if >50% of players approve it
  - Tie defaults to valid
  - Players cannot vote on their own words (auto-approved if others approve)
- **Scoring Rules**:
  - Base: 1 point per letter in valid word
  - Bonus: +5 points for word ≥8 letters
  - Invalid words: 0 points
  - Duplicate submissions: Only first submitter gets points
- **Score Calculation**: After moderation, points automatically tallied and leaderboard updated
- **Round Summary**: Show all valid words, invalid words, scores earned per player

### 6. Victory & Game End
- **Score Tracking**: Persistent player scores across rounds
- **Victory Condition**: First player to reach target score wins
- **Game Over Screen**: Final scores with winner highlighting and full word history
- **New Game Option**: Reset to lobby while preserving players

### 7. Technical Architecture
- **LiveView + GenServer**: Game logic in `AnagramsServer`, UI in `AnagramsLive`
- **Dynamic Supervision**: Each session runs as supervised GenServer process
- **Registry-based Lookup**: Sessions registered for efficient process discovery
- **PubSub Integration**: Real-time updates to all session participants
- **Cleanup Workers**: Automated disconnected player and session cleanup
- **State Persistence**: Game state survives player disconnections and reconnections
- **Language/Locale Support**: Full i18n with Gettext integration
- **Word Validation Logic**: Server-side letter counting and validation

## State Machine

### Game Phases
1. **`:lobby`** - Players joining, setting ready status, viewing base word
2. **`:playing`** - Active round with word submission and timer
3. **`:moderation`** - Collective word validation and scoring
4. **`:round_end`** - Score summary and leaderboard display
5. **`:game_over`** - Final scores display and restart options

### State Transitions

```elixir
:lobby -> :playing
  Conditions:
    - At least 1 player
    - All players ready
    - Base word selected
  Trigger: start_game action
  Effects:
    - Start round timer
    - Clear all previous submissions
    - Enable word input

:playing -> :moderation
  Conditions:
    - Timer expires OR
    - All players manually end their submissions
  Trigger: Automatic (timer) or collective ready
  Effects:
    - Lock all submissions
    - Display all words for validation
    - Enable voting interface

:moderation -> :round_end
  Conditions: All players submitted their votes
  Trigger: Automatic when votes complete
  Effects:
    - Calculate scores based on votes
    - Update player totals
    - Show round summary

:round_end -> :lobby
  Conditions: No player reached target score
  Trigger: next_round action
  Effects:
    - Reset all players to not ready
    - Generate new base word
    - Clear submissions and votes

:round_end -> :game_over
  Conditions: Any player score >= target_score
  Trigger: Automatic
  Effects: Mark winner, show final leaderboard

:game_over -> :lobby
  Trigger: start_new_game action
  Effects: Complete game reset while preserving players
```

### Player State Transitions

```elixir
nil -> Player{connected: true, ready: false, score: 0}
  Trigger: join_session with valid nickname

Player{connected: true} -> Player{connected: false, disconnected_at: timestamp}
  Trigger: leave_session or browser disconnect

Player{connected: false} -> Player{connected: true, disconnected_at: nil}
  Trigger: rejoin via mark_connected or restore_session

Player{ready: false} -> Player{ready: true}
  Trigger: set_ready(true)

Player{ready: true} -> Player{ready: false}
  Trigger: set_ready(false) or round transition
```

## Rule System

### Session Rules
- **Minimum Players**: 1+ players (solo practice mode supported)
- **Base Word Generation**: Random selection from language-specific word lists
- **Base Word Categories**:
  - Short: 8-10 letters (e.g., "CREATING", "REACTION")
  - Medium: 11-13 letters (e.g., "PERSONALITY", "GENERATIONS")
  - Long: 14+ letters (e.g., "REPRESENTATION", "CHARACTERISTIC")

### Player Rules
- **Nickname Uniqueness**: Within session scope only
- **Ready Requirement**: Must set ready status to enable game start
- **Reconnection Grace**: 10-minute window for automatic reconnection
- **Submission Limits**: Unlimited words per round (before timer expires)

### Game Start Rules
- **Ready Check**: All connected players must be ready
- **Minimum Players**: 1+ players
- **Base Word Loading**: Automatic word selection based on length/language settings

### Gameplay Rules
- **Letter Validation**: Words must use only letters from base word
- **Letter Count Enforcement**: Each letter can only be used as many times as it appears in base word
- **Minimum Length**: Words must meet configured minimum length (3-5 letters)
- **Case Insensitive**: All words normalized to uppercase for validation
- **Duplicate Prevention**: Players cannot submit same word twice in one round
- **Live Feedback**: Real-time validation as player types (green/red indicator)
- **Word Editing**: Players can remove their submitted words before round ends

### Moderation Rules
- **Democratic Validation**: Simple majority vote determines validity
- **Self-Vote Exclusion**: Players cannot vote on their own words
- **Vote Visibility**: Votes shown after moderation phase completes
- **Dispute Resolution**: Ties default to valid (benefit of doubt)
- **Moderation Timeout**: If votes not submitted within 2 minutes, auto-approve all words

### Scoring Rules
- **Base Score**: 1 point per letter in valid word
- **Length Bonus**: +5 points for words with 8+ letters
- **Validity Requirement**: Only approved words score points
- **Duplicate Handling**: If multiple players submit same word, only first gets points
- **Score Persistence**: Scores accumulate across rounds until game_over

### Cleanup Rules
- **Player Cleanup**: Disconnected players removed after 10 minutes
- **Session Cleanup**: Entire session terminated after 1 hour of inactivity
- **Activity Tracking**: Any player action updates session activity timestamp
- **Cleanup Frequency**: Automated cleanup runs every 5 minutes

## Data Structure

```elixir
%AnagramsState{
  session_id: string(),
  language: :en | :ru,
  word_length_category: :short | :medium | :long, # 8-10, 11-13, 14+
  round_duration: integer(), # minutes: 3, 5, 7, 10
  min_word_length: integer(), # 3, 4, or 5
  target_score: integer(), # 30, 50, 75, 100
  phase: :lobby | :playing | :moderation | :round_end | :game_over,

  players: %{user_id => %{
    nickname: string(),
    ready: boolean(),
    connected: boolean(),
    disconnected_at: DateTime.t() | nil,
    score: integer(), # Total score across all rounds
    current_round_words: [string()], # Words submitted this round
  }},

  current_base_word: string(), # The word to make anagrams from

  # Round management
  round_number: integer(),
  round_start_time: DateTime.t() | nil,
  timer_ref: reference() | nil,
  time_remaining: integer() | nil, # Seconds

  # Submissions and voting
  all_submissions: %{word => [user_id]}, # Map of word to list of submitters
  votes: %{word => %{user_id => boolean()}}, # Nested map: word -> voter_id -> approve?
  validated_words: %{word => boolean()}, # Final validation results

  # Game metadata
  game_ever_started: boolean(),
  cleanup_timer_ref: reference(),
  created_at: DateTime.t(),
  last_activity: DateTime.t(),

  # Winner tracking
  winner_id: user_id | nil
}
```

## Word Lists

### Base Words by Language and Length

**English:**
- **Short (8-10)**: CREATING, REACTION, TRIANGLE, ABSOLUTE, COMPLETE, QUESTION, PRACTICE, KEYBOARD, STANDARD, DIRECTOR
- **Medium (11-13)**: PERSONALITY, GENERATIONS, TEMPERATURE, COMFORTABLE, OBSERVATION, DEMONSTRATE, CELEBRATION, EDUCATIONAL, PHOTOGRAPHY, ALTERNATIVE
- **Long (14+)**: REPRESENTATION, CHARACTERISTIC, RESPONSIBILITY, IMPLEMENTATION, TRANSFORMATION, EXTRAORDINARY, ADMINISTRATOR, CONGRATULATIONS, UNFORTUNATELY, MULTIPLICATION

**Russian:**
- **Short (8-10)**: СОЗДАНИЕ, РЕАКЦИЯ, ПРАКТИКА, СТАНДАРТ, ДИРЕКТОР, КЛАВИАТУРА, ТРЕУГОЛЬНИК, ВОПРОС
- **Medium (11-13)**: ТЕМПЕРАТУРА, НАБЛЮДЕНИЕ, ДЕМОНСТРАЦИЯ, ОБРАЗОВАНИЕ, ФОТОГРАФИЯ, АЛЬТЕРНАТИВА, ПРАЗДНОВАТЬ, КОМФОРТАБЕЛЬНЫЙ
- **Long (14+)**: ПРЕДСТАВИТЕЛЬСТВО, ХАРАКТЕРИСТИКА, ОТВЕТСТВЕННОСТЬ, ТРАНСФОРМАЦИЯ, АДМИНИСТРАТОР, ПОЗДРАВЛЕНИЯ, УМНОЖЕНИЕ

### Word Validation Algorithm

```elixir
def valid_word?(word, base_word, min_length) do
  # Normalize to uppercase
  word = String.upcase(word)
  base = String.upcase(base_word)

  # Check minimum length
  String.length(word) >= min_length &&

  # Check all letters available in base word
  word
  |> String.graphemes()
  |> Enum.all?(fn letter ->
    count_in_word = Enum.count(String.graphemes(word), &(&1 == letter))
    count_in_base = Enum.count(String.graphemes(base), &(&1 == letter))
    count_in_word <= count_in_base
  end)
end
```

### Scoring Calculation

```elixir
def calculate_score(word, is_valid, is_duplicate) do
  cond do
    !is_valid -> 0
    is_duplicate -> 0
    true ->
      base_points = String.length(word)
      bonus = if String.length(word) >= 8, do: 5, else: 0
      base_points + bonus
  end
end
```

## User Interface

### Lobby Screen
- Session link display with copy button
- Player list with ready indicators
- Game settings summary (language, word length, round time, target score)
- Base word preview (large, centered)
- Ready/Not Ready toggle button
- Start Game button (enabled when all ready)

### Playing Screen
- **Header**: Round number, timer countdown (with color warnings: green >60s, yellow 30-60s, red <30s)
- **Base Word**: Large, prominent display of current base word
- **Input Section**:
  - Text input with live validation feedback (green checkmark/red X)
  - Submit button
  - Character count and letter availability display
- **Player's Words**: List of submitted words with delete button for each
- **Leaderboard Sidebar**: Current scores (minimized/collapsible)
- **End Round Early** button (optional, for all players who finished)

### Moderation Screen
- **Instructions**: "Vote on each word - valid or invalid?"
- **Word List**: All unique submitted words grouped or listed
- **Per Word**:
  - The word itself (large font)
  - Submitted by: Player name(s)
  - Valid/Invalid toggle or checkbox
  - Vote count indicator (optional)
- **Submit Votes** button
- **Timer**: Optional 2-minute moderation timeout

### Round End Screen
- **Round Summary**:
  - Valid words by player with points earned
  - Invalid words (grayed out)
  - Duplicate words indicator
- **Updated Leaderboard**: Full scores with highlights for top 3
- **Next Round** button (only if no winner)
- **Continue** button transitions to :game_over if winner exists

### Game Over Screen
- **Winner Announcement**: Large display of winner nickname and final score
- **Final Leaderboard**: All players ranked
- **Game History**: Optionally show all rounds and words
- **Start New Game** button

## Technical Requirements

- **Phoenix LiveView**: Real-time UI with minimal JavaScript
- **GenServer Supervision**: Fault-tolerant game state management
- **PubSub Broadcasting**: Session-wide real-time updates
- **Registry**: Efficient session process lookup
- **Gettext**: Full internationalization support (English/Russian)
- **DaisyUI + Tailwind**: Modern component-based styling
- **Heroicons**: Consistent iconography
- **LocalStorage Integration**: Client-side persistence via JS hooks for user_id
- **Audio Support**: Timer notification sounds
- **Live Validation**: Client-side word validation with server-side confirmation

## Implementation Notes

### Letter Counting Logic
Use Elixir's `String.graphemes/1` to properly handle Unicode characters in Russian words. For each submitted word, validate that each letter appears no more times than in the base word.

### Vote Aggregation
For each word, collect votes from all players except the submitter(s). Calculate simple majority. If 50/50 tie, default to valid.

### Duplicate Detection
Track submission order by timestamp. First player to submit a word gets credit; subsequent identical submissions marked as duplicates and score 0.

### Moderation Timeout
If not all players vote within 2 minutes, auto-approve remaining unvoted words to keep game flowing.

### Base Word Selection
Randomly select from predefined word lists based on language and length category. Ensure words have good letter variety for interesting gameplay.

### Reconnection Handling
When player reconnects during `:playing`, restore their submitted words list. During `:moderation`, allow them to submit votes. Preserve their score across disconnections.

### Performance Optimization
For sessions with many players (10+), consider pagination or grouping in moderation phase to avoid overwhelming UI.
