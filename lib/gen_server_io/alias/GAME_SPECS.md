# Alias Game Functionality Specification

## Overview
A minimalistic real-time Alias game built with Phoenix LiveView, utilizing PubSub and GenServers for state management with comprehensive session persistence, player reconnection, and automated cleanup.

## Core Features

### 1. Session Management
- **Create Session**: Simple button to create new game session with configurable settings
- **Unique Links**: Each session gets a unique hash-based URL (`/:session_id`)
- **Difficulty Selection**: Choose word set difficulty (Simple/Easy/Medium/Difficult) during session creation
- **Language Support**: English and Russian language options with localized UI
- **Target Score**: Configurable winning score (10, 15, 20, 30, 50, 100 points)
- **No Authentication**: No logins, registrations, or persistent user accounts
- **Session Persistence**: Sessions survive server restarts and player disconnections
- **Automatic Cleanup**: Sessions automatically cleaned after 1 hour of inactivity

### 2. Player Connection & Persistence
- **Unique User IDs**: Each player gets a persistent UUID stored in localStorage
- **Automatic Reconnection**: Players automatically rejoin their previous session/team on page refresh
- **Nickname Reclamation**: Disconnected players' nicknames can be reclaimed after timeout
- **Connection Status**: Players marked as connected/disconnected with timestamps
- **Graceful Degradation**: Missing players don't break game flow; replacement explainers assigned automatically

### 3. Lobby System
- **Join via Link**: Users join by visiting the unique session URL
- **Nickname Entry**: Each user can set their display name (must be unique within session)
- **Team Management**: 
  - Join existing teams (automatically numbered: Team 1, Team 2, etc.)
  - Create new teams with "Join New Team" button
  - Waiting room for unassigned players (AFK tolerance)
  - Team preservation during active games (no team changes during gameplay)
- **Ready State**: Only team members must press "Ready" to start game
- **AFK Handling**: Players in waiting room don't block game start
- **Flexible Start**: Can start with just 1 team (2+ players) or multiple teams
- **Explainer Assignment**: First explainer automatically determined, with smart fallback logic

### 4. Game Flow
- **Turn-based Gameplay**: Teams take turns explaining words with automatic rotation
- **Timed Rounds**: Each turn has a 60-second timer with real-time countdown
- **Timer Audio**: Sound notification when time expires (`/sounds/timer_end.mp3`)
- **Word Presentation**: Current explainer sees words prominently; others see hidden placeholder
- **Action Buttons**: "Next" button to progress through words (disabled after timer expires)
- **Real-time Visibility**: All actions immediately visible to all players via PubSub
- **Word Scoring**: Post-round scoring system with +1/0/-1 points per word
- **Smart Explainer Handoff**: If explainer disconnects, team member can take over seamlessly
- **Auto Turn End**: Round automatically ends when timer reaches zero or words exhausted

### 5. Scoring & Victory
- **Round Scoring**: Words default to +1 but can be adjusted in scoring phase
- **Team Score Tracking**: Persistent team scores across rounds
- **Victory Condition**: First team to reach target score wins
- **Game Over Screen**: Final scores with winner highlighting
- **New Game Option**: Reset to lobby while preserving players and teams

### 6. Technical Architecture
- **LiveView + GenServer**: Game logic in `GameServer`, UI in `GameLive`
- **Dynamic Supervision**: Each session runs as supervised GenServer process
- **Registry-based Lookup**: Sessions registered for efficient process discovery
- **PubSub Integration**: Real-time updates to all session participants
- **Cleanup Workers**: Automated disconnected player and session cleanup
- **State Persistence**: Game state survives player disconnections and reconnections
- **Language/Locale Support**: Full i18n with Gettext integration

## State Machine

### Game Phases
1. **`:lobby`** - Players joining, forming teams, setting ready status
2. **`:playing`** - Active game with word explanation and timer
3. **`:round_end`** - Word scoring and team score calculation
4. **`:game_over`** - Final scores display and restart options

### State Transitions

```elixir
:lobby -> :playing
  Conditions: 
    - At least 1 team with members
    - Total team members >= 2 
    - All team members ready
    - Valid explainer available
  Trigger: start_game by designated first explainer

:playing -> :round_end
  Conditions:
    - Timer expires (60 seconds) OR
    - All words exhausted via next_word actions
  Trigger: Automatic (timer) or explainer actions

:round_end -> :lobby
  Conditions: Team score < target_score after round scoring
  Trigger: next_round action
  Effects: 
    - Add round score to current team
    - Reset all players to not ready
    - Calculate next explainer/team rotation
    - Return to lobby for next round start

:round_end -> :game_over  
  Conditions: Team score >= target_score after round scoring
  Trigger: next_round action (automatic)
  Effects: Mark winning team, show final scores

:game_over -> :lobby
  Trigger: start_new_game action
  Effects: Complete game reset while preserving players

Any Phase -> :lobby
  Trigger: reset_to_lobby action (admin function)
  Effects: Hard reset of game state
```

### Player State Transitions

```elixir
nil -> Player{connected: true, team: nil, ready: false}
  Trigger: join_session with valid nickname

Player{connected: true} -> Player{connected: false, disconnected_at: timestamp}
  Trigger: leave_session or browser disconnect

Player{connected: false} -> Player{connected: true, disconnected_at: nil}
  Trigger: rejoin via mark_connected or restore_session

Player{team: nil} -> Player{team: "Team N"}  
  Trigger: join_team action
  Conditions: Not during active gameplay

Player{team: "Team N"} -> Player{team: nil, ready: false}
  Trigger: leave_team action  
  Conditions: Not during active gameplay

Player{ready: false} -> Player{ready: true}
  Trigger: set_ready(true)
  Conditions: Player has team assignment

Player{ready: true} -> Player{ready: false}  
  Trigger: set_ready(false) or team change or round transition
```

## Rule System

### Team Rules
- **Minimum Size**: No minimum team size, but 2+ total players across all teams required to start
- **Team Creation**: Dynamic team creation with sequential numbering (Team 1, Team 2, ...)
- **Team Changes**: Only allowed in lobby phase; locked during active gameplay
- **Empty Teams**: Automatically removed unless game has started (preserves structure)
- **Team Persistence**: Teams maintained during player disconnections if game started

### Player Rules
- **Nickname Uniqueness**: Within session scope only
- **Ready Requirement**: Must be on team and set ready status to enable game start
- **Waiting Room**: Players without teams don't block game start
- **Reconnection Grace**: 10-minute window for automatic reconnection
- **Explainer Eligibility**: Any connected team member can explain if original explainer disconnects

### Game Start Rules
- **Explainer Priority**: Designated first explainer starts game, with fallbacks to ready players
- **Minimum Players**: 2+ total players across all teams
- **Ready Check**: All team members must be ready (waiting room ignored)
- **Word Availability**: Automatic word set loading based on difficulty/language

### Gameplay Rules  
- **Explainer Actions**: Only current explainer (or substitute) can advance words
- **Word Progression**: "Next" action counts as +1 point (explained), can be adjusted in scoring
- **Time Limits**: 60-second rounds with automatic termination
- **Word States**: Each word gets status (:next) and adjustable score (-1, 0, +1)
- **Round End**: Triggered by timer expiration or word exhaustion

### Scoring Rules
- **Default Scoring**: All words initially worth +1 point  
- **Score Adjustment**: Post-round scoring allows -1, 0, or +1 per word
- **Team Scoring**: Round total added to current team's score
- **Victory Condition**: First team to reach/exceed target score wins
- **Tie Breaking**: First team to reach target in turn order wins

### Cleanup Rules
- **Player Cleanup**: Disconnected players removed after 10 minutes
- **Session Cleanup**: Entire session terminated after 1 hour of inactivity  
- **Activity Tracking**: Any player action updates session activity timestamp
- **Cleanup Frequency**: Automated cleanup runs every 5 minutes

## Data Structure

```elixir
%GameState{
  session_id: string(),
  difficulty: :simple | :easy | :medium | :difficult,
  language: :en | :ru,
  target_score: integer(), # 10, 15, 20, 30, 50, 100
  phase: :lobby | :playing | :round_end | :game_over,
  players: %{user_id => %{
    nickname: string(), 
    team: string() | nil, 
    ready: boolean(),
    connected: boolean(),
    disconnected_at: DateTime.t() | nil
  }},
  teams: [%{name: string(), members: [user_id], score: integer()}],
  current_team: integer(), # Index into teams array
  current_explainer: user_id | nil,
  next_explainer: user_id | nil, # Pre-calculated for efficiency
  current_word: string() | nil,
  words_used: [%{word: string(), status: :next, score: integer()}],
  remaining_words: [string()],
  round_start_time: DateTime.t() | nil,
  timer_ref: reference() | nil,
  time_remaining: integer() | nil, # Seconds
  game_ever_started: boolean(), # Affects cleanup behavior
  cleanup_timer_ref: reference(), # Automated cleanup
  created_at: DateTime.t(),
  last_activity: DateTime.t() # For session timeout
}
```

## Word Sets
- **Simple**: Basic everyday words and concepts (WordSets module)
- **Easy**: Common objects and actions  
- **Medium**: Mix of concrete and abstract concepts
- **Difficult**: Complex concepts, technical terms, cultural references
- **Multilingual**: Full English and Russian word sets per difficulty

## User Interface
- **Responsive Design**: Mobile-first with DaisyUI components
- **Real-time Updates**: Immediate state synchronization via PubSub
- **Accessibility**: Proper ARIA labels and keyboard navigation
- **Visual Feedback**: Color-coded ready states, timer warnings, score highlights
- **Audio Cues**: Timer expiration sound with autoplay
- **Internationalization**: Complete Russian/English localization
- **Progressive Enhancement**: Works with JavaScript disabled (form fallbacks)

## Technical Requirements
- **Phoenix LiveView**: Real-time UI with minimal JavaScript
- **GenServer Supervision**: Fault-tolerant game state management  
- **PubSub Broadcasting**: Session-wide real-time updates
- **Registry**: Efficient session process lookup
- **Gettext**: Full internationalization support
- **DaisyUI + Tailwind**: Modern component-based styling
- **Heroicons**: Consistent iconography
- **LocalStorage Integration**: Client-side persistence via JS hooks
- **Audio Support**: Timer notification sounds