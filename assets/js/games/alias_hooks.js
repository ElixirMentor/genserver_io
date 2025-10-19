// Alias game hooks

export const AliasUserDataLoader = {
  mounted() {
    // Try to load user data from localStorage
    const userId = localStorage.getItem("alias_user_id");
    const nickname = localStorage.getItem("alias_nickname");

    if (userId && nickname) {
      // Send existing user data to LiveView for reconnection
      this.pushEvent("restore_session", {
        user_id: userId,
        nickname: nickname
      });
    }

    // Listen for save events from LiveView
    this.handleEvent("save_user_data", ({ user_id, nickname }) => {
      localStorage.setItem("alias_user_id", user_id);
      localStorage.setItem("alias_nickname", nickname);
    });
  }
};

export const AliasNicknameForm = {
  mounted() {
    // Auto-focus the nickname input when the form is mounted
    const input = this.el.querySelector('input[type="text"]');
    if (input) {
      input.focus();
    }
  }
};

export const AliasSettingsLoader = {
  mounted() {
    // Load any saved settings from localStorage
    const theme = localStorage.getItem("alias_theme");

    if (theme) {
      this.pushEvent("load_settings", { theme });
    }

    // Listen for save_settings event
    this.handleEvent("save_settings", (settings) => {
      Object.entries(settings).forEach(([key, value]) => {
        localStorage.setItem(`alias_${key}`, value);
      });
    });
  }
};
