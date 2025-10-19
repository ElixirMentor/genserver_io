// Anagrams game hooks

export const AnagramsUserIdManager = {
  mounted() {
    // Try to load user_id from localStorage
    const userId = localStorage.getItem("anagrams_user_id");

    if (userId) {
      // Send existing user_id to LiveView for reconnection
      this.pushEvent("user_id_received", { user_id: userId });
    }

    // Listen for save_user_id event from LiveView
    this.handleEvent("save_user_id", ({ user_id }) => {
      localStorage.setItem("anagrams_user_id", user_id);
    });
  }
};

export const AnagramsSettingsLoader = {
  mounted() {
    // Load any saved settings from localStorage
    const theme = localStorage.getItem("anagrams_theme");

    if (theme) {
      this.pushEvent("load_settings", { theme });
    }

    // Listen for save_settings event
    this.handleEvent("save_settings", (settings) => {
      Object.entries(settings).forEach(([key, value]) => {
        localStorage.setItem(`anagrams_${key}`, value);
      });
    });
  }
};

export const AnagramsCopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText || this.el.textContent;

      navigator.clipboard.writeText(text).then(() => {
        // Show a temporary success indicator
        const originalText = this.el.textContent;
        this.el.textContent = "Copied!";

        setTimeout(() => {
          this.el.textContent = originalText;
        }, 1000);
      });
    });
  }
};
