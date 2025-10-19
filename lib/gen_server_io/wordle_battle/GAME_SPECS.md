# Wordle Battle Game Specifications

## Overview

Wordle Battle is a competitive, real-time word-guessing game where players race against the clock to guess 5-letter words. Players earn points based on how quickly and efficiently they guess each word, with the highest score winning when time expires.

## Game Flow

### 1. Lobby Phase

- Players join the session using a shareable session ID
- Each player chooses a unique nickname
- Players mark themselves as "Ready"
- Game starts when all players are ready
- Session duration can be configured (1, 3, or 5 minutes)
- Language can be selected (English or Russian)

### 2. Playing Phase

- Timer counts down from the configured duration
- All players start with the same first word
- Players have 6 attempts to guess each 5-letter word
- After correctly guessing or failing a word (6 attempts), a new word is assigned
- Each player progresses through words independently
- Real-time leaderboard shows current scores and progress
- Game ends when timer reaches zero

### 3. Game Over Phase

- Final rankings displayed
- Winner highlighted with total points
- Average attempts per word shown for each player
- Players can start a new game (returns to lobby)
- Players can return home to create a new session

## Scoring System

Points are awarded based on the number of attempts needed to guess a word:

- **1 attempt**: 6 points (Perfect guess!)
- **2 attempts**: 4 points
- **3 attempts**: 3 points
- **4-6 attempts**: 2 points
- **Failed** (6 attempts without guessing): 0 points

## Word Assignment

- First word is randomly selected and assigned to all players simultaneously
- Subsequent words come from a shared sequence:
  - When a player completes a word, they receive the next word in sequence
  - If the sequence doesn't have a word at that position, a new random word is generated and added to the sequence
  - This ensures all players can potentially get the same words, but in different order based on their progress

## Word Validation

### Guess Checking Algorithm (Two-Pass)

1. **First Pass**: Mark exact position matches
   - Compare each letter in the guess with the corresponding position in the target word
   - Mark matching letters as `:correct` (green)

2. **Second Pass**: Mark present but wrong position
   - For letters not marked as correct, check if they exist elsewhere in the target word
   - Track used letters to avoid double-counting
   - Mark present letters as `:present` (yellow)
   - Mark remaining letters as `:wrong` (gray)

### Example

Target word: `ABBEY`
Guess: `BABES`

- Position 0: B vs A → wrong
- Position 1: A vs B → present (A exists in position 0)
- Position 2: B vs B → correct
- Position 3: E vs E → correct
- Position 4: S vs Y → wrong

Result: `[:present, :wrong, :correct, :correct, :wrong]`

## Game State Structure

```elixir
%State{
  session_id: String.t(),
  session_duration: 1 | 3 | 5,
  language: :en | :ru,
  phase: :lobby | :playing | :game_over,
  players: %{
    user_id => %{
      nickname: String.t(),
      ready: boolean(),
      connected: boolean(),
      disconnected_at: DateTime.t() | nil,
      current_word: String.t() | nil,
      current_attempts: [
        %{guess: String.t(), result: [letter_result()]}
      ],
      words_completed: non_neg_integer(),
      words_guessed: non_neg_integer(),
      total_attempts: non_neg_integer(),
      score: non_neg_integer(),
      word_history: [
        %{word: String.t(), guessed: boolean(), attempts: integer(), points: integer()}
      ]
    }
  },
  used_words: [String.t()],
  session_start_time: DateTime.t() | nil,
  session_end_time: DateTime.t() | nil,
  timer_ref: reference() | nil,
  time_remaining: non_neg_integer() | nil,
  game_ever_started: boolean(),
  winner_id: String.t() | nil,
  final_rankings: [
    %{user_id: String.t(), nickname: String.t(), score: integer(), avg_attempts: float()}
  ],
  created_at: DateTime.t(),
  last_activity: DateTime.t()
}
```

## Player Management

### Connection Handling

- Players can disconnect and reconnect without losing progress
- User ID and nickname are stored in browser localStorage
- Disconnected players marked with `disconnected_at` timestamp
- Players disconnected > 10 minutes are removed from the session
- Sessions inactive > 1 hour are automatically terminated

### Reconnection Flow

1. Player's browser loads page with saved user_id and nickname
2. LiveView sends "restore_session" event to server
3. Server marks player as connected if they exist in the session
4. Player's current progress is preserved and displayed

## Real-time Updates

### PubSub Broadcasting

- Every state change broadcasts to all connected players
- Timer ticks broadcast every second during gameplay
- Players subscribe to topic: `"game:#{session_id}"`
- Updates trigger automatic UI re-renders via LiveView

### Update Types

- `:game_update` - Full state changes (player joins, word completed, etc.)
- `:time_update` - Timer countdown (sent every second)

## Multi-language Support

### English (:en)

- 200 common 5-letter words
- All uppercase (ABOUT, ABOVE, ABUSE, etc.)
- Latin alphabet

### Russian (:ru)

- 100 common 5-letter words
- All uppercase Cyrillic (БАГАЖ, БАЛКА, БАНДА, etc.)
- Cyrillic alphabet

## Technical Implementation

### GenServer Architecture

- One GenServer process per game session
- Process registered via Registry with session_id
- DynamicSupervisor creates sessions on demand
- Automatic cleanup via periodic timer (every 5 minutes)

### Client API

```elixir
# Session Management
Server.create_session(session_id, duration, language)
Server.session_exists?(session_id)
Server.get_state(session_id)

# Player Actions
Server.join_session(session_id, user_id, nickname)
Server.mark_connected(session_id, user_id)
Server.mark_disconnected(session_id, user_id)
Server.set_ready(session_id, user_id, ready)

# Game Flow
Server.start_game(session_id)
Server.submit_guess(session_id, user_id, guess)
Server.new_game(session_id)
```

### State Machine Transitions

```
:lobby ──(all players ready + start_game)──> :playing
:playing ──(timer expires)──> :game_over
:game_over ──(new_game)──> :lobby (scores reset, players preserved)
```

## UI/UX Features

### Lobby

- Session ID display for sharing
- Player list with ready status
- Ready/Not Ready toggle button
- Start Game button (enabled when all ready)
- Game settings display (duration, language)

### Playing

- Two-column layout: game board + leaderboard
- 6×5 grid showing current word attempts
- Color-coded letter tiles (green/yellow/gray)
- Input form for submitting guesses
- Real-time timer with color indicators:
  - Green: > 60 seconds remaining
  - Yellow: 30-60 seconds
  - Red: < 30 seconds
- Live leaderboard sorted by score
- Current stats: attempt count, score, words guessed

### Game Over

- Winner highlight with gradient background
- Final rankings with positions (#1, #2, #3, etc.)
- Average attempts per word for each player
- New Game button (rematch)
- Home button (create new session)

## Error Handling

### Validation Errors

- `invalid_length` - Guess is not exactly 5 letters
- `invalid_word` - Word not in dictionary
- `nickname_taken` - Another player has this nickname
- `player_not_found` - User ID doesn't exist in session
- `not_in_lobby` - Action requires lobby phase
- `not_playing` - Action requires playing phase
- `not_game_over` - Action requires game over phase
- `not_all_ready` - Cannot start without all players ready
- `no_players` - Cannot start with zero players

### User-Facing Messages

All error messages are translated via gettext for multi-language support.

## Performance Characteristics

- Handles 2-8 players per session comfortably
- Minimal memory footprint per session (~few KB)
- No database required (all state in GenServer memory)
- Automatic cleanup prevents memory leaks
- PubSub ensures efficient broadcasts
- LiveView provides instant UI updates without polling

## Future Enhancements

Potential improvements for future versions:

1. **Expanded Word Lists**: Add more languages and larger dictionaries
2. **Daily Challenges**: Same word for all players globally
3. **Achievement System**: Badges for perfect games, streaks, etc.
4. **Difficulty Levels**: Easy (common words) vs Hard (obscure words)
5. **Power-ups**: Hint system, letter reveals, extra attempts
6. **Tournament Mode**: Bracket-style competitions
7. **Replay System**: Watch past games
8. **Statistics**: Personal best, win rate, favorite words
9. **Custom Word Lists**: User-uploaded dictionaries
10. **Voice Chat**: Integrated communication for players

## Credits

Inspired by Wordle by Josh Wardle. Implemented as a learning project to demonstrate:

- Elixir/OTP patterns
- Phoenix LiveView real-time capabilities
- GenServer-based game architecture
- Multi-player state synchronization
- Clean code organization
