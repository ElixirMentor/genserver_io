# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a monorepo containing multiple Phoenix LiveView game applications built with Elixir. The repository serves as a learning/demonstration project for GenServer-based real-time multiplayer games using Phoenix LiveView, PubSub, and OTP patterns.

## Contained Projects

The repository contains several independent Phoenix applications:

- **gen_server_io**: Base Phoenix scaffold (minimal/template project)
- **alias**: Real-time Alias/Taboo word guessing game with team-based gameplay
- **anagrams**: Multiplayer anagrams game with democratic word validation
- **truth_or_lie**: (Additional game project)

## Development Commands

### Main Repository Commands

When working in the root `gen_server_io` directory:

- `mix setup` - Install and setup dependencies, build assets
- `mix phx.server` - Start Phoenix server (visit http://localhost:4000)
- `iex -S mix phx.server` - Start server with IEx console

### Code Quality

- `mix precommit` - **Always run before committing**: compiles with `--warnings-as-errors`, unlocks unused deps, formats code, and runs tests
- `mix test` - Run all tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test --failed` - Re-run only failed tests
- `mix format` - Format code according to `.formatter.exs`

### Asset Management

- `mix assets.setup` - Install Tailwind CSS and esbuild if missing
- `mix assets.build` - Build assets (Tailwind + esbuild)
- `mix assets.deploy` - Build minified assets for production

## Architecture Patterns

### GenServer-Based Game Sessions

Both `alias` and `anagrams` follow the same core architectural pattern:

**Session Management with Registry + DynamicSupervisor:**
```elixir
# Each game session is a GenServer registered via Registry
{:via, Registry, {AppName.GameRegistry, session_id}}

# Sessions are dynamically supervised
DynamicSupervisor.start_child(AppName.GameSupervisor, {GameServer, session_id})
```

**Key Components:**
1. **GameServer GenServer** (`alias/lib/alias/game_server.ex`, `anagrams/lib/anagrams/game/server.ex`)
   - Manages all game state for a single session
   - Handles player actions, game logic, timers, and validation
   - Survives player disconnections

2. **LiveView Controller** (e.g., `alias_web/live/game_live.ex`)
   - Renders UI and handles user interactions
   - Subscribes to PubSub for real-time updates
   - Delegates all game logic to GenServer

3. **PubSub Broadcasting**
   - Session-scoped updates: `Phoenix.PubSub.broadcast(AppName.PubSub, "game:#{session_id}", message)`
   - All connected players receive real-time state updates

4. **Player Persistence**
   - UUID-based player identification (stored in localStorage via JS hooks)
   - Players can reconnect after page refresh or disconnection
   - 10-minute grace period for disconnected players
   - Session cleanup after 1 hour of inactivity

### State Machine Pattern

Games use explicit phase transitions in GenServer state:
- alias: `:lobby` → `:playing` → `:round_end` → `:game_over`
- anagrams: `:lobby` → `:playing` → `:moderation` → `:round_end` → `:game_over`

### Application Supervision Tree

Standard Phoenix setup with PubSub and dynamic supervisors:
```elixir
children = [
  AppWeb.Telemetry,
  {Phoenix.PubSub, name: App.PubSub},
  {Registry, keys: :unique, name: App.GameRegistry},
  {DynamicSupervisor, name: App.GameSupervisor, strategy: :one_for_one},
  AppWeb.Endpoint
]
```

## Phoenix v1.8 Critical Guidelines

This project uses Phoenix 1.8+ with LiveView 1.1+. **Always consult AGENTS.md for complete Phoenix/Elixir guidelines.** Key reminders:

### LiveView Templates
- **Always begin templates with** `<Layouts.app flash={@flash} ...>` wrapper
- **Use `to_form/2` for all forms**, never pass changesets to templates
- **Forms in templates**: `<.form for={@form} id="unique-id">`, access fields as `@form[:field]`

### HEEx Interpolation Rules
- In attributes: `{@value}` or `{expression}`
- In tag bodies for values: `{@value}`
- In tag bodies for blocks: `<%= if/for/cond/case do %> ... <% end %>`
- **Never use `<%= %>` in attributes**

### LiveView Streams (Not Regular Lists)
When rendering collections, use streams to prevent memory issues:
```elixir
# In LiveView
stream(socket, :messages, [new_msg])
stream(socket, :messages, items, reset: true)  # for filtering
stream_delete(socket, :messages, msg)

# In template (must have phx-update="stream" and consume @streams.name)
<div id="messages" phx-update="stream">
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.text}
  </div>
</div>
```

### Elixir Language Gotchas
- **No `else if`**: Use `cond` or `case` for multiple conditions
- **List access**: Never `list[i]`, always `Enum.at(list, i)` or pattern matching
- **Struct fields**: Use `struct.field`, never `struct[:field]` (structs don't implement Access)
- **Immutable rebinding**: Rebind the result of expressions, not inside them:
  ```elixir
  # WRONG
  if condition do
    socket = assign(socket, :val, val)
  end

  # CORRECT
  socket = if condition do
    assign(socket, :val, val)
  end
  ```

### Navigation
- Use `<.link navigate={path}>` or `<.link patch={path}>`
- **Never use deprecated** `live_redirect` or `live_patch`

### HTTP Requests
- **Always use `:req` (Req) library** for HTTP requests
- **Avoid** `:httpoison`, `:tesla`, `:httpc`

## Testing

Uses `Phoenix.LiveViewTest` and `LazyHTML`:
- **Test via selectors**, not raw HTML: `assert has_element?(view, "#form-id")`
- Always add unique DOM IDs to elements in templates for testing
- Form tests: `render_submit/2`, `render_change/2`
- Debug selectors with LazyHTML:
  ```elixir
  document = LazyHTML.from_fragment(render(view))
  LazyHTML.filter(document, "selector") |> IO.inspect()
  ```

## Project-Specific Details

For detailed information about individual game implementations, refer to:
- `alias/CLAUDE.md` - Alias game architecture and rules
- `anagrams/CLAUDE.md` - Anagrams game architecture and word validation
- `AGENTS.md` - Comprehensive Phoenix/Elixir development guidelines (required reading)

## Common Patterns in This Codebase

### GenServer via_tuple Pattern
```elixir
defp via_tuple(session_id) do
  {:via, Registry, {AppName.GameRegistry, session_id}}
end

GenServer.call(via_tuple(session_id), :get_state)
```

### Cleanup and Timeout Handling
Both games implement automatic cleanup:
- Periodic cleanup timer (every 5 minutes) removes stale disconnected players
- Session timeout (1 hour of inactivity) terminates the GenServer
- Disconnect timeout (10 minutes) removes players who haven't reconnected

### Real-time Updates Pattern
```elixir
# In GenServer after state changes
defp broadcast_update(state) do
  Phoenix.PubSub.broadcast(AppName.PubSub, "game:#{state.session_id}", {:game_update, state})
end

# In LiveView mount/handle_info
Phoenix.PubSub.subscribe(AppName.PubSub, "game:#{session_id}")

def handle_info({:game_update, state}, socket) do
  {:noreply, assign(socket, game_state: state)}
end
```
