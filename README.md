# GenServer.io

**Real-time multiplayer games powered by Elixir, Phoenix LiveView, and GenServer**

A collection of fun, interactive games built to showcase the power of Elixir's concurrency model and Phoenix LiveView's real-time capabilities. Each game is a learning project demonstrating clean OTP patterns and WebSocket-based multiplayer architecture.

🎮 **Live Demo**: [GenServer.io](https://genserver.io)

## Tech Stack

- **Elixir** - Functional programming with the BEAM VM
- **Phoenix LiveView** - Real-time server-rendered UI with WebSockets
- **GenServer** - Each game session runs as an isolated OTP process
- **PubSub** - Phoenix PubSub for broadcasting game state updates
- **Gettext** - Multi-language support (English & Russian)

## Getting Started

```bash
# Install dependencies and setup
mix setup

# Start the Phoenix server
mix phx.server

# Or start with IEx console
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) to play!

## Architecture Overview

### Core Principles

Each game follows the same elegant architecture:

1. **One GenServer per game session** - All game state lives in a single process
2. **No database** - Everything is in-memory for simplicity
3. **No mailer** - Just share a link to play
4. **LiveView only** - Server-rendered real-time UI
5. **PubSub for sync** - State changes broadcast to all connected players

### How It Works

```
User Browser (LiveView)
    ↕️ WebSocket
Phoenix LiveView Process
    ↕️ GenServer.call/cast
Game Session (GenServer)
    ↕️ PubSub broadcast
All Connected Players
```

## Contributing

We welcome contributions! Whether it's adding a new game, supporting a new language, or improving existing code.

### Project Rules

Keep it simple and educational:

- ✅ **Use LiveView** - All UI must be server-rendered LiveView
- ✅ **Use GenServer** - Game state managed by GenServer processes
- ✅ **Use PubSub** - Real-time sync via Phoenix.PubSub
- ❌ **No database** - Keep everything in-memory
- ❌ **No mailer** - Share links directly
- ❌ **No external services** - Self-contained games only

### Adding a New Game

1. **Create the LiveView module**

```bash
# Create the game LiveView
touch lib/gen_server_io_web/live/your_game.ex
```

```elixir
defmodule GenServerIoWeb.YourGameLive do
  use GenServerIoWeb, :live_view

  alias GenServerIo.YourGame.Server
  alias Phoenix.PubSub

  @impl true
  def mount(params, _session, socket) do
    # Setup logic here
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <!-- Your game UI here -->
    </Layouts.app>
    """
  end
end
```

2. **Create the GenServer**

```bash
# Create the game server
mkdir -p lib/gen_server_io/your_game
touch lib/gen_server_io/your_game/server.ex
```

```elixir
defmodule GenServerIo.YourGame.Server do
  use GenServer

  # Client API
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def join_session(session_id, user_id, nickname) do
    GenServer.call(via_tuple(session_id), {:join, user_id, nickname})
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    state = %{
      session_id: Keyword.fetch!(opts, :session_id),
      players: %{},
      phase: :lobby
      # Add your game state fields
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:join, user_id, nickname}, _from, state) do
    # Add player logic
    new_state = put_in(state.players[user_id], %{nickname: nickname})
    broadcast_update(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  # Broadcast state changes to all connected players
  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(
      GenServerIo.PubSub,
      "session:#{state.session_id}",
      {:state_updated, state}
    )
  end

  defp via_tuple(session_id) do
    {:via, Registry, {GenServerIo.YourGame.Registry, session_id}}
  end
end
```

3. **Add to supervision tree**

In `lib/gen_server_io/application.ex`:

```elixir
children = [
  # ... existing children ...
  {Registry, keys: :unique, name: GenServerIo.YourGame.Registry},
  {DynamicSupervisor, name: GenServerIo.YourGame.Supervisor, strategy: :one_for_one}
]
```

4. **Add routes**

In `lib/gen_server_io_web/router.ex`:

```elixir
scope "/", GenServerIoWeb do
  pipe_through :browser

  live "/your_game", YourGameLive
  live "/your_game/:session_id", YourGameLive
end
```

5. **Add to home page**

Update `lib/gen_server_io_web/controllers/page_html/home.html.heex` with a game card.

6. **Create gettext domain**

```bash
# Create translation template
touch priv/gettext/your_game.pot

# Create English translations
touch priv/gettext/en/LC_MESSAGES/your_game.po
```

In your LiveView, use domain-specific translations:

```elixir
dgettext("your_game", "Join Game")
```

### Adding a New Language

We use Phoenix Gettext for internationalization. Each game has its own translation domain.

1. **Create locale directory**

```bash
# For example, adding French (fr)
mkdir -p priv/gettext/fr/LC_MESSAGES
```

2. **Copy and translate .po files**

```bash
# Copy all English translations
cp priv/gettext/en/LC_MESSAGES/*.po priv/gettext/fr/LC_MESSAGES/

# Edit each .po file
# Change: "Language: en\n" → "Language: fr\n"
# Translate all msgstr fields
```

Example `priv/gettext/fr/LC_MESSAGES/alias.po`:

```po
msgid ""
msgstr ""
"Language: fr\n"

#: lib/gen_server_io_web/live/alias.ex:22
msgid "Join Game"
msgstr "Rejoindre la partie"

#: lib/gen_server_io_web/live/alias.ex:268
msgid "Start Game"
msgstr "Commencer la partie"
```

3. **Add language to dropdowns**

Update language selectors in each game's LiveView:

```elixir
<select name="language" phx-change="change_language">
  <option value="en">English</option>
  <option value="ru">Русский</option>
  <option value="fr">Français</option>
</select>
```

4. **Update language change handler**

```elixir
def handle_event("change_language", %{"language" => language}, socket) do
  language_atom = String.to_existing_atom(language)
  Gettext.put_locale(GenServerIoWeb.Gettext, language)
  {:noreply, assign(socket, language: language_atom)}
end
```

5. **Extract and merge translations**

After adding `dgettext/2` calls to your code:

```bash
# Extract all translations from code into .pot files
mix gettext.extract --merge
```

## Development

### Code Quality

```bash
# Format code
mix format

# Run tests
mix test

# Run pre-commit checks (compile with warnings-as-errors, format, test)
mix precommit
```

### Project Structure

```
lib/
├── gen_server_io/           # Business logic
│   ├── alias/              # Alias game
│   │   ├── server.ex       # GenServer managing game state
│   │   └── word_list.ex    # Game-specific modules
│   ├── anagrams/           # Anagrams game
│   │   ├── server.ex
│   │   └── word_validator.ex
│   └── truth_or_lie/       # Truth or Lie game
│       └── server.ex
└── gen_server_io_web/      # Web layer
    ├── live/               # LiveView modules
    │   ├── alias.ex
    │   ├── anagrams.ex
    │   └── truth_or_lie.ex
    └── router.ex

priv/gettext/               # Translations
├── alias.pot               # Translation templates
├── anagrams.pot
├── truth_or_lie.pot
├── en/LC_MESSAGES/         # English translations
│   ├── alias.po
│   ├── anagrams.po
│   └── truth_or_lie.po
└── ru/LC_MESSAGES/         # Russian translations
    ├── alias.po
    ├── anagrams.po
    └── truth_or_lie.po
```

## Learn More

- **Phoenix Framework**: https://www.phoenixframework.org/
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view
- **Elixir GenServer**: https://hexdocs.pm/elixir/GenServer.html
- **Phoenix PubSub**: https://hexdocs.pm/phoenix_pubsub
- **Gettext**: https://hexdocs.pm/gettext

## License

This is an open-source learning project. Feel free to explore, learn, and contribute!

## Credits

Made with ❤️ by [1703.lu](https://1703.lu) using Elixir & Phoenix LiveView
