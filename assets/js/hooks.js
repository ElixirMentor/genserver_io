// Import hooks from each game
import * as AliasHooks from "./games/alias_hooks"
import * as AnagramsHooks from "./games/anagrams_hooks"
import * as TruthOrLieHooks from "./games/truth_or_lie_hooks"
import * as WordleBattleHooks from "./games/wordle_battle_hooks"

// Export all hooks with their game-specific names
// This allows each game to have isolated hook implementations
export const {
  AliasUserDataLoader,
  AliasNicknameForm,
  AliasSettingsLoader
} = AliasHooks;

export const {
  AnagramsUserIdManager,
  AnagramsSettingsLoader,
  AnagramsCopyToClipboard
} = AnagramsHooks;

export const {
  TruthOrLieUserIdManager
} = TruthOrLieHooks;

export const {
  WordleBattleUserDataLoader,
  WordleBattleSettingsLoader,
  WordleBattleNicknameForm,
  WordleBattleGuessInput
} = WordleBattleHooks;

// Re-export with generic names for templates that use them
// (templates will need to be updated to use the game-specific names)
export const UserDataLoader = AliasHooks.AliasUserDataLoader;
export const UserIdManager = TruthOrLieHooks.TruthOrLieUserIdManager;
export const SettingsLoader = AliasHooks.AliasSettingsLoader;
export const CopyToClipboard = AnagramsHooks.AnagramsCopyToClipboard;
export const NicknameForm = AliasHooks.AliasNicknameForm;
