Perfect! Now I have all the details. Let me create the complete specification:

```markdown
# Truth or Lie Game Functionality Specification

## Overview
A minimalistic real-time social deduction game built with Phoenix LiveView, utilizing PubSub and GenServers for state management with session persistence, player reconnection, and automated cleanup. Players create questions about themselves with one true answer and two lies, then compete to identify the truth in others' questions.

## Core Features

### 1. Session Management
- **Create Session**: Simple button to create new game session with configurable settings
- **Unique Links**: Each session gets a unique hash-based URL (`/:session_id`)
- **Win Condition**: Configurable target score (5, 10, 15, 20, 25, 30 points)
- **No Authentication**: No logins, registrations, or persistent user accounts
- **Session Persistence**: Sessions survive server restarts and player disconnections
- **Automatic Cleanup**: Sessions automatically cleaned after 1 hour of inactivity

### 2. Player Connection & Persistence
- **Unique User IDs**: Each player gets a persistent UUID stored in localStorage
- **Automatic Reconnection**: Players automatically rejoin their session on page refresh
- **Nickname Reclamation**: Disconnected players' nicknames can be reclaimed after timeout
- **Connection Status**: Players marked as connected/disconnected with timestamps
- **Graceful Degradation**: Disconnected players' progress preserved; game continues for others

### 3. Lobby System
- **Join via Link**: Users join by visiting the unique session URL
- **Nickname Entry**: Each user can set their display name (must be unique within session)
- **Individual Play**: Each player competes individually (no teams)
- **Ready State**: All connected players must press "Ready" to start game
- **Minimum Players**: Requires 2+ players to start
- **Settings Display**: Show target score in lobby
- **Round Tracking**: Display current round number and scores from previous rounds

### 4. Game Flow

#### Phase 1: Question Creation (3 minutes)
- **Private Creation**: Each player independently creates their question
- **Question Format**:
  - One question about themselves
  - Three answer options (A, B, C)
  - Mark one answer as truth, other two as lies
- **Timer**: 3-minute countdown for all players
- **Ready Mechanism**: Can mark ready before timer expires
- **Auto-advance**: When all players ready OR timer expires
- **Incomplete Submissions**: If player doesn't finish:
  - Empty question displays as blank
  - Missing answers display as empty slots
  - Can proceed with partial data (2 answers instead of 3)

#### Phase 2: Guessing Questions (Sequential)
- **Question Order**: Player 1 → Player 2 → Player 3 → etc. (join order)
- **Per Question Flow**:
  - Display current player's question and 3 answers
  - Question author sees others guessing (spectator mode for their own question)
  - Other players select one answer (A, B, or C)
  - 1-minute timer per question
  - Players can press "Ready" after selecting answer
  - Auto-advance when: all non-authors ready OR timer expires
- **Disconnected Players**: If not reconnected by end of timer, count as 0 points (no selection)

#### Phase 3: Results Display (Per Question)
- **Reveal Truth**: Highlight which answer was correct
- **Show Guesses**: Display each player's selection with correct/incorrect indicator
- **Score Updates**:
  - Question author: +2 points if ALL other players guessed wrong (fooled everyone)
  - Question author: 0 points if anyone guessed correctly
  - Guessers: +1 point for correct guess, 0 for wrong guess
- **Current Standings**: Show updated total scores for all players
- **Continue Button**: Proceed to next question

#### Phase 4: Round End
- **Final Scores**: Display all players ranked by score
- **Round Summary**: Show questions from this round with answers
- **Check Win Condition**:
  - If any player reached target score → Game Over screen
  - If no winner → Return to Lobby for next round

### 5. Scoring System
- **Correct Guess**: +1 point per correct identification of truth
- **Perfect Deception**: +2 points to author if they fooled ALL other players
- **Partial Deception**: 0 points to author if anyone guessed correctly
- **No Answer**: 0 points (timer expired or disconnected)
- **Cumulative Scoring**: Scores persist across multiple rounds until winner

### 6. Victory & Game End
- **Win Condition**: First player to reach target score wins
- **Game Over Screen**:
  - Winner announcement with final score
  - Full rankings of all players
  - Statistics: questions created, correct guesses, times fooled everyone
  - Full game history (all rounds and questions)
- **New Game Option**: Reset to lobby, clear all scores, start fresh

### 7. Technical Architecture
- **LiveView + GenServer**: Game logic in `TruthOrLieServer`, UI in `TruthOrLieLive`
- **Dynamic Supervision**: Each session runs as supervised GenServer process
- **Registry-based Lookup**: Sessions registered for efficient process discovery
- **PubSub Integration**: Real-time updates to all session participants
- **Cleanup Workers**: Automated disconnected player and session cleanup
- **State Persistence**: Game state survives player disconnections and reconnections

## State Machine

### Game Phases
1. **`:lobby`** - Players joining, setting ready status, viewing scores
2. **`:creating`** - Players writing questions and answers (3 min timer)
3. **`:guessing`** - Players guessing answers sequentially (1 min per question)
4. **`:results`** - Showing results after each question
5. **`:round_end`** - Round summary and score display
6. **`:game_over`** - Final winner announcement

### State Transitions

```elixir
:lobby -> :creating
  Conditions:
    - At least 2 players
    - All players ready
  Trigger: start_game action
  Effects:
    - Start 3-minute creation timer
    - Clear all player submissions
    - Enable question creation UI

:creating -> :guessing
  Conditions:
    - All players pressed ready OR 3-minute timer expired
  Trigger: Automatic (timer) or all players ready
  Effects:
    - Lock all question submissions
    - Set current_question_index to 0
    - Start 1-minute guessing timer for first question
    - Enable guessing UI

:guessing -> :results
  Conditions:
    - All non-author players pressed ready OR 1-minute timer expired
  Trigger: Automatic (timer) or all players ready
  Effects:
    - Lock current question guesses
    - Calculate scores for this question
    - Display correct answer and player guesses

:results -> :guessing
  Conditions:
    - More questions remain (current_question_index < total questions)
    - Continue button pressed
  Trigger: continue_to_next_question action
  Effects:
    - Increment current_question_index
    - Start 1-minute timer for next question
    - Clear previous guesses

:results -> :round_end
  Conditions:
    - All questions completed (current_question_index >= total questions)
    - Continue button pressed
  Trigger: continue_to_round_end action
  Effects:
    - Calculate round statistics
    - Display round summary

:round_end -> :game_over
  Conditions:
    - Any player score >= target_score
  Trigger: Automatic check
  Effects:
    - Determine winner (highest score)
    - Display final statistics

:round_end -> :lobby
  Conditions:
    - No player reached target_score
  Trigger: next_round action
  Effects:
    - Increment round number
    - Preserve scores
    - Reset all players to not ready
    - Clear question submissions

:game_over -> :lobby
  Trigger: start_new_game action
  Effects:
    - Complete game reset
    - Clear all scores
    - Reset round number to 1
    - Preserve players and nicknames
```

### Player State Transitions

```elixir
nil -> Player{connected: true, ready: false, total_score: 0}
  Trigger: join_session with valid nickname

Player{connected: true} -> Player{connected: false, disconnected_at: timestamp}
  Trigger: leave_session or browser disconnect

Player{connected: false} -> Player{connected: true, disconnected_at: nil}
  Trigger: rejoin via mark_connected or restore_session

Player{ready: false} -> Player{ready: true}
  Trigger: set_ready(true) during :lobby or :creating or :guessing

Player{ready: true} -> Player{ready: false}
  Trigger: Phase transition to :lobby

Player{question: nil} -> Player{question: %Question{}}
  Trigger: submit_question during :creating phase

Player{current_guess: nil} -> Player{current_guess: "A"}
  Trigger: select_answer during :guessing phase
```

## Rule System

### Session Rules
- **Minimum Players**: 2+ players required to start
- **Target Score Options**: 5, 10, 15, 20, 25, or 30 points
- **Round-based**: Multiple rounds until winner emerges
- **Question Order**: Sequential based on player join order

### Player Rules
- **Nickname Uniqueness**: Within session scope only
- **Ready Requirement**: Must set ready status to enable game start
- **Reconnection Grace**: 10-minute window for automatic reconnection
- **Score Persistence**: Scores maintained across rounds and disconnections

### Game Start Rules
- **Ready Check**: All connected players must be ready in lobby
- **Minimum Players**: 2+ players
- **Question Requirement**: Each player creates one question per round

### Creation Phase Rules (3 minutes)
- **Question Format**: Free text, any length
- **Answer Count**: Exactly 3 answers (A, B, C)
- **Truth Marking**: Must mark exactly 1 answer as truth
- **Incomplete Submission**: Allowed (displays with empty fields)
- **Early Ready**: Can mark ready before timer expires
- **Auto-advance**: When all ready OR timer expires

### Guessing Phase Rules (1 minute per question)
- **Sequential Order**: One question at a time, in player join order
- **Author Spectating**: Question author cannot guess their own question
- **Selection Required**: Players select A, B, or C
- **Ready Mechanism**: Can press ready after selecting
- **Timer Override**: If all non-authors ready, skip remaining time
- **No Selection**: If timer expires with no selection, counts as wrong (0 points)
- **Disconnected Players**: Count as 0 points if not reconnected by timer expiration

### Scoring Rules
- **Correct Guess**: +1 point to guesser
- **Wrong Guess**: 0 points to guesser
- **Perfect Deception**: +2 points to author if ALL other players guessed wrong
- **Partial Deception**: 0 points to author if anyone guessed correctly
- **No Answer**: 0 points (timer expired without selection)
- **Cumulative Scoring**: Scores persist across rounds
- **Winner Determination**: First player to reach/exceed target score

### Results Display Rules
- **Per Question**: Show results immediately after each question's guessing
- **Information Shown**:
  - Which answer was the truth (highlighted)
  - Each player's selection (marked correct/incorrect)
  - Points awarded to each player for this question
  - Updated total scores for all players
- **Visibility**: All players see all results

### Round End Rules
- **Trigger**: After all questions in round completed
- **Display**: Full round summary with all questions and answers
- **Win Check**: If any player >= target_score, trigger game over
- **Continue**: Otherwise, return to lobby for next round

### Cleanup Rules
- **Player Cleanup**: Disconnected players removed after 10 minutes
- **Session Cleanup**: Entire session terminated after 1 hour of inactivity
- **Activity Tracking**: Any player action updates session activity timestamp
- **Cleanup Frequency**: Automated cleanup runs every 5 minutes

## Data Structure

```elixir
%TruthOrLieState{
  session_id: string(),
  target_score: integer(), # 5, 10, 15, 20, 25, or 30
  phase: :lobby | :creating | :guessing | :results | :round_end | :game_over,

  # Round tracking
  round_number: integer(),

  players: %{user_id => %{
    nickname: string(),
    ready: boolean(),
    connected: boolean(),
    disconnected_at: DateTime.t() | nil,

    # Current round progress
    question: %{
      text: string(),
      answers: [
        %{label: "A", text: string(), is_truth: boolean()},
        %{label: "B", text: string(), is_truth: boolean()},
        %{label: "C", text: string(), is_truth: boolean()}
      ]
    } | nil,

    # Current question guessing
    current_guess: "A" | "B" | "C" | nil,

    # Scoring
    total_score: integer(), # Cumulative across all rounds
    round_score: integer(), # Points earned this round only

    # Statistics
    questions_created: integer(),
    correct_guesses: integer(),
    times_fooled_everyone: integer()
  }},

  # Guessing phase tracking
  current_question_index: integer() | nil, # Which player's question (0-based)
  player_order: [user_id], # Order for sequential questions

  # Timing
  phase_timer_ref: reference() | nil,
  phase_start_time: DateTime.t() | nil,
  phase_duration: integer() | nil, # Seconds (180 for creating, 60 for guessing)
  time_remaining: integer() | nil,

  # Results tracking (for current question being displayed)
  current_results: %{
    question_author: user_id,
    correct_answer: "A" | "B" | "C",
    player_guesses: %{user_id => %{
      guess: "A" | "B" | "C" | nil,
      correct: boolean(),
      points_awarded: integer()
    }},
    author_points: integer() # 0 or 2
  } | nil,

  # Game metadata
  game_ever_started: boolean(),
  cleanup_timer_ref: reference(),
  created_at: DateTime.t(),
  last_activity: DateTime.t(),

  # Winner tracking
  winner_id: user_id | nil,
  final_rankings: [%{
    user_id: string(),
    nickname: string(),
    total_score: integer(),
    questions_created: integer(),
    correct_guesses: integer(),
    times_fooled_everyone: integer()
  }]
}
```

## User Interface

### Lobby Screen
```
┌────────────────────────────────────────────────┐
│  TRUTH OR LIE                                  │
│                                                │
│  Room Code: ABC123  [Copy Link]               │
│  Target Score: 15 points                       │
│  Current Round: 1                              │
│                                                │
├────────────────────────────────────────────────┤
│  Players (3):                                  │
│  👤 Alice         ✓ Ready      Score: 0       │
│  👤 Bob           ⏳ Waiting    Score: 0       │
│  👤 You (Charlie) ✓ Ready      Score: 0       │
│                                                │
│  [Ready / Not Ready]                           │
│  [Start Game] ← enabled when all ready        │
└────────────────────────────────────────────────┘
```

### Creation Phase Screen
```
┌────────────────────────────────────────────────┐
│  CREATE YOUR QUESTION        Time: 02:47       │
├────────────────────────────────────────────────┤
│                                                │
│  Write a question about yourself:              │
│  ┌──────────────────────────────────────────┐ │
│  │ What is my favorite hobby?               │ │
│  └──────────────────────────────────────────┘ │
│                                                │
│  Answer A:                                     │
│  ┌──────────────────────────────────────────┐ │
│  │ Reading books                            │ │
│  └──────────────────────────────────────────┘ │
│  ○ This is the TRUTH  ⚪ This is a LIE       │
│                                                │
│  Answer B:                                     │
│  ┌──────────────────────────────────────────┐ │
│  │ Playing video games                      │ │
│  └──────────────────────────────────────────┘ │
│  ⚪ This is the TRUTH  ○ This is a LIE       │
│                                                │
│  Answer C:                                     │
│  ┌──────────────────────────────────────────┐ │
│  │ Hiking                                   │ │
│  └──────────────────────────────────────────┘ │
│  ⚪ This is the TRUTH  ○ This is a LIE       │
│                                                │
│  [Mark as Ready]                               │
│                                                │
│  Other players: Alice ✓  Bob ⏳               │
└────────────────────────────────────────────────┘
```

### Guessing Phase Screen (Your turn to guess)
```
┌────────────────────────────────────────────────┐
│  ALICE'S QUESTION           Time: 00:47        │
├────────────────────────────────────────────────┤
│                                                │
│  What is my favorite hobby?                    │
│                                                │
│  Select your answer:                           │
│                                                │
│  ⚪ A) Reading books                           │
│  ○ B) Playing video games   ← selected        │
│  ⚪ C) Hiking                                  │
│                                                │
│  [Submit & Ready]                              │
│                                                │
├────────────────────────────────────────────────┤
│  Waiting for:                                  │
│  Bob ⏳  Charlie ✓                            │
└────────────────────────────────────────────────┘
```

### Guessing Phase Screen (Your own question - spectating)
```
┌────────────────────────────────────────────────┐
│  YOUR QUESTION              Time: 00:47        │
├────────────────────────────────────────────────┤
│                                                │
│  What is my favorite hobby?                    │
│                                                │
│  A) Reading books              ✓ (TRUTH)       │
│  B) Playing video games        ✗ (LIE)         │
│  C) Hiking                     ✗ (LIE)         │
│                                                │
│  👀 Watching others guess...                   │
│                                                │
├────────────────────────────────────────────────┤
│  Players guessing:                             │
│  Bob ⏳  Charlie ✓                            │
└────────────────────────────────────────────────┘
```

### Results Screen (After each question)
```
┌────────────────────────────────────────────────┐
│  RESULTS - ALICE'S QUESTION                    │
├────────────────────────────────────────────────┤
│                                                │
│  What is my favorite hobby?                    │
│                                                │
│  🟢 A) Reading books           ← TRUTH         │
│  ⚪ B) Playing video games                     │
│  ⚪ C) Hiking                                  │
│                                                │
├────────────────────────────────────────────────┤
│  Who guessed what:                             │
│                                                │
│  👤 Bob        → A ✅ Correct!    +1 point     │
│  👤 Charlie    → B ❌ Wrong        0 points    │
│                                                │
│  🎭 Alice (author): Someone guessed it! 0 pts  │
│                                                │
├────────────────────────────────────────────────┤
│  Current Scores:                               │
│  🥇 Alice      7 points                        │
│  🥈 Bob        6 points                        │
│  🥉 Charlie    3 points                        │
│                                                │
│  [Continue to Next Question]                   │
└────────────────────────────────────────────────┘
```

### Results Screen (Perfect Deception)
```
┌────────────────────────────────────────────────┐
│  RESULTS - CHARLIE'S QUESTION                  │
├────────────────────────────────────────────────┤
│                                                │
│  Where was I born?                             │
│                                                │
│  ⚪ A) New York                                │
│  🟢 B) Tokyo              ← TRUTH              │
│  ⚪ C) London                                  │
│                                                │
├────────────────────────────────────────────────┤
│  Who guessed what:                             │
│                                                │
│  👤 Alice      → A ❌ Wrong        0 points    │
│  👤 Bob        → C ❌ Wrong        0 points    │
│                                                │
│  🎉 Charlie (author): FOOLED EVERYONE! +2 pts  │
│                                                │
├────────────────────────────────────────────────┤
│  Current Scores:                               │
│  🥇 Charlie    5 points                        │
│  🥈 Alice      4 points                        │
│  🥉 Bob        3 points                        │
│                                                │
│  [Continue to Next Question]                   │
└────────────────────────────────────────────────┘
```

### Round End Screen
```
┌────────────────────────────────────────────────┐
│  🏁 ROUND 1 COMPLETE                           │
├────────────────────────────────────────────────┤
│                                                │
│  Scores after Round 1:                         │
│                                                │
│  🥇 Alice      7 points  (needs 8 more)        │
│  🥈 Bob        6 points  (needs 9 more)        │
│  🥉 Charlie    5 points  (needs 10 more)       │
│                                                │
│  Target: First to 15 points wins!              │
│                                                │
├────────────────────────────────────────────────┤
│  Round 1 Questions:                            │
│  [View All Questions & Answers]                │
│                                                │
│  [Start Next Round]                            │
└────────────────────────────────────────────────┘
```

### Game Over Screen
```
┌────────────────────────────────────────────────┐
│  🏆 GAME OVER                                  │
│                                                │
│  👑 WINNER: ALICE!                             │
│     Final Score: 16 points                     │
│     Questions Created: 4                       │
│     Correct Guesses: 8/12                      │
│     Perfect Deceptions: 2                      │
│                                                │
├────────────────────────────────────────────────┤
│  Final Rankings:                               │
│                                                │
│  🥇 Alice      16 pts  (8/12 correct, 2x fool) │
│  🥈 Bob        14 pts  (9/12 correct, 1x fool) │
│  🥉 Charlie    11 pts  (6/12 correct, 3x fool) │
│                                                │
├────────────────────────────────────────────────┤
│  Game Summary:                                 │
│  Rounds Played: 4                              │
│  Total Questions: 12                           │
│                                                │
│  [View All Questions]  [Start New Game]  [Home]│
└────────────────────────────────────────────────┘
```

## Technical Requirements

- **Phoenix LiveView**: Real-time UI with minimal JavaScript
- **GenServer Supervision**: Fault-tolerant game state management
- **PubSub Broadcasting**: Session-wide real-time updates
- **Registry**: Efficient session process lookup
- **DaisyUI + Tailwind**: Modern component-based styling
- **Heroicons**: Consistent iconography
- **LocalStorage Integration**: Client-side persistence via JS hooks for user_id
- **Audio Support**: Timer notification sounds (optional)
- **Form Validation**: Client and server-side validation for questions/answers
- **Rich Text Support**: Handle multi-line questions and answers

## Implementation Notes

### Question Validation
```elixir
def valid_question?(question) do
  # Question text
  question_valid = String.trim(question.text) != ""

  # At least 1 answer provided
  answers_provided = Enum.count(question.answers, fn a ->
    String.trim(a.text) != ""
  end) >= 1

  # Exactly 1 truth marked (if any answers provided)
  truth_count = Enum.count(question.answers, & &1.is_truth)
  truth_valid = truth_count == 1 or answers_provided == false

  question_valid and (answers_provided == false or truth_valid)
end
```

### Score Calculation
```elixir
def calculate_scores(question_author_id, correct_answer, guesses) do
  # Calculate guesser scores
  guesser_scores = Enum.map(guesses, fn {player_id, guess} ->
    points = if guess == correct_answer, do: 1, else: 0
    {player_id, points}
  end)

  # Calculate author score
  all_wrong = Enum.all?(guesses, fn {_, guess} ->
    guess != correct_answer
  end)

  author_points = if all_wrong and map_size(guesses) > 0, do: 2, else: 0

  {guesser_scores, author_points}
end
```

### Timer Management
```elixir
def start_phase_timer(state, phase, duration_seconds) do
  # Cancel existing timer
  if state.phase_timer_ref do
    Process.cancel_timer(state.phase_timer_ref)
  end

  # Start new timer with 1-second ticks
  timer_ref = :timer.send_interval(1000, :tick)

  %{state |
    phase: phase,
    phase_timer_ref: timer_ref,
    phase_start_time: DateTime.utc_now(),
    phase_duration: duration_seconds,
    time_remaining: duration_seconds
  }
end

def handle_info(:tick, state) do
  time_remaining = state.time_remaining - 1

  if time_remaining <= 0 do
    # Timer expired, advance phase
    {:noreply, handle_timer_expiration(state)}
  else
    # Broadcast time update
    Phoenix.PubSub.broadcast(
      TruthOrLie.PubSub,
      "session:#{state.session_id}",
      {:time_update, time_remaining}
    )

    {:noreply, %{state | time_remaining: time_remaining}}
  end
end
```

### Question Order Management
```elixir
def initialize_question_order(players) do
  players
  |> Map.keys()
  |> Enum.sort() # Consistent order based on user_id
end

def get_current_question_author(state) do
  Enum.at(state.player_order, state.current_question_index)
end

def get_current_question(state) do
  author_id = get_current_question_author(state)
  get_in(state, [:players, author_id, :question])
end
```

### Ready Check Logic
```elixir
# For creation phase
def all_players_ready_creating?(state) do
  state.players
  |> Map.values()
  |> Enum.filter(& &1.connected)
  |> Enum.all?(& &1.ready)
end

# For guessing phase (exclude author)
def all_guessers_ready?(state) do
  author_id = get_current_question_author(state)

  state.players
  |> Map.reject(fn {id, _} -> id == author_id end)
  |> Map.values()
  |> Enum.filter(& &1.connected)
  |> Enum.all?(& &1.ready)
end
```

### Incomplete Submission Handling
```elixir
def display_question(question) do
  %{
    text: question.text || "",
    answers: [
      %{label: "A", text: get_answer_text(question, 0)},
      %{label: "B", text: get_answer_text(question, 1)},
      %{label: "C", text: get_answer_text(question, 2)}
    ]
  }
end

defp get_answer_text(question, index) do
  case Enum.at(question.answers, index) do
    nil -> ""
    answer -> answer.text || ""
  end
end
```

### Reconnection Handling
- **During :creating**: Restore player's partial question submission
- **During :guessing**: Restore player's current guess selection
- **During :results**: Show results for current question
- **Score persistence**: Always maintained across disconnections

### Mobile Optimization
- **Responsive forms**: Stack question/answers vertically on mobile
- **Large touch targets**: Buttons minimum 44×44px
- **Readable text**: Larger font sizes for questions
- **Collapsible sections**: Hide other players' status on small screens

### Accessibility
- **ARIA labels**: All interactive elements properly labeled
- **Keyboard navigation**: Tab through form fields, radio buttons
- **Screen reader announcements**: Timer updates, phase changes, score updates
- **Color contrast**: Ensure sufficient contrast for correct/incorrect indicators

### Performance Optimization
- **Throttle timer broadcasts**: Only send updates when display changes (per second)
- **Lazy load statistics**: Calculate stats only when viewing game over screen
- **PubSub filtering**: Only broadcast to relevant players (e.g., results)

### Security Considerations
- **Server-side validation**: Never trust client for correct answer
- **Hide truth from clients**: During guessing, only server knows correct answer
- **Rate limiting**: Prevent spam submissions during creation phase
- **XSS prevention**: Sanitize user-generated question/answer text

### Edge Cases
- **Empty questions**: Display blank but allow game to continue
- **All disconnected except one**: Pause timer, wait for reconnections
- **Tie at target score**: Player who reached it first (in that round) wins
- **Mid-round disconnection**: Skip their turn, don't block game flow
```
