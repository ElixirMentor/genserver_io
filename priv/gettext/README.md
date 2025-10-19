# Gettext Translations Organization

This project uses **domain-based** gettext organization, where each game has its own translation domain.

## Structure

```
priv/gettext/
├── README.md                    # This file
├── errors.pot                   # Error messages (shared)
├── default.pot                  # Default domain (shared)
├── alias.pot                    # Alias game translations template
├── anagrams.pot                 # Anagrams game translations template
├── truth_or_lie.pot             # Truth or Lie game translations template
└── en/LC_MESSAGES/              # English translations
    ├── errors.po
    ├── default.po
    ├── alias.po                 # Alias game English translations
    ├── anagrams.po              # Anagrams game English translations
    └── truth_or_lie.po          # Truth or Lie game English translations
```

## How to Use in Code

### Alias Game
```elixir
# In alias.ex or any alias game file
dgettext("alias", "Join Game")
dgettext("alias", "Points to win")
```

### Anagrams Game
```elixir
# In anagrams.ex or any anagrams game file
dgettext("anagrams", "Submit your answer")
dgettext("anagrams", "Waiting for votes")
```

### Truth or Lie Game
```elixir
# In truth_or_lie.ex or any truth_or_lie game file
dgettext("truth_or_lie", "Create Your Question")
dgettext("truth_or_lie", "Submit & Ready")
```

### Error Messages (Shared)
```elixir
# For error messages across the app
dgettext("errors", "Something went wrong")
```

## Adding New Translations

### 1. Extract translations from code
```bash
mix gettext.extract --merge
```

This will scan all Elixir files for `dgettext/2` calls and extract them into the appropriate `.pot` files.

### 2. Add translations to locale files
Edit the `.po` files in each locale directory (e.g., `en/LC_MESSAGES/alias.po`):

```po
#: lib/gen_server_io_web/live/alias.ex:556
msgid "Join Game"
msgstr "Join Game"  # English translation
```

### 3. For new locales (e.g., Russian)
```bash
# Create Russian locale directory
mkdir -p priv/gettext/ru/LC_MESSAGES

# Copy and translate the .po files
cp priv/gettext/en/LC_MESSAGES/alias.po priv/gettext/ru/LC_MESSAGES/alias.po
# Then edit ru/LC_MESSAGES/alias.po to add Russian translations
```

Example Russian translation:
```po
#: lib/gen_server_io_web/live/alias.ex:556
msgid "Join Game"
msgstr "Присоединиться к игре"
```

## Benefits of This Organization

1. **Separation of Concerns**: Each game has its own translation file
2. **Easier Collaboration**: Translators can work on one game at a time
3. **Better Organization**: No mixing of game-specific strings
4. **Scalability**: Easy to add new games or remove old ones
5. **Isolated Changes**: Updating one game's translations doesn't affect others

## Current Status

- ✅ **Alias**: 53 messages extracted and organized
- ✅ **Anagrams**: 14 messages extracted and organized
- ✅ **Truth or Lie**: 17 messages extracted and organized

## Next Steps

1. ✅ Add `dgettext("anagrams", "...")` calls to anagrams.ex - DONE
2. ✅ Add `dgettext("truth_or_lie", "...")` calls to truth_or_lie.ex - DONE
3. ✅ Run `mix gettext.extract --merge` to update .pot and .po files - DONE
4. Add translations for other locales (e.g., Russian) - TODO

All games now use domain-specific translations! To add a new locale:
```bash
mkdir -p priv/gettext/ru/LC_MESSAGES
cp priv/gettext/en/LC_MESSAGES/*.po priv/gettext/ru/LC_MESSAGES/
# Then edit the .po files to add Russian translations
```
