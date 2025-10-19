// Wordle Battle game hooks

export const WordleBattleUserDataLoader = {
  mounted() {
    // Try to load user data from localStorage
    const userId = localStorage.getItem("wordle_battle_user_id");
    const nickname = localStorage.getItem("wordle_battle_nickname");

    if (userId && nickname) {
      // Send existing user data to LiveView for reconnection
      this.pushEvent("restore_session", { user_id: userId, nickname });
    }

    // Listen for save_user_data event from LiveView
    this.handleEvent("save_user_data", ({ user_id, nickname }) => {
      localStorage.setItem("wordle_battle_user_id", user_id);
      localStorage.setItem("wordle_battle_nickname", nickname);
    });
  }
};

export const WordleBattleSettingsLoader = {
  mounted() {
    // Load any saved settings from localStorage
    const language = localStorage.getItem("wordle_battle_language");

    if (language) {
      this.pushEvent("restore_saved_settings", { language });
    }

    // Listen for save_settings event
    this.handleEvent("save_settings", (settings) => {
      Object.entries(settings).forEach(([key, value]) => {
        localStorage.setItem(`wordle_battle_${key}`, value);
      });
    });
  }
};

export const WordleBattleNicknameForm = {
  mounted() {
    // Auto-focus nickname input
    const input = this.el.querySelector('input[name="nickname"]');
    if (input) {
      input.focus();
    }
  }
};

export const WordleBattleGuessInput = {
  mounted() {
    // Auto-focus guess input
    this.el.focus();
  },

  updated() {
    // Refocus after update (when guess is cleared)
    this.el.focus();
  }
};
