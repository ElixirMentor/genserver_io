// Truth or Lie game hooks

export const TruthOrLieUserIdManager = {
  mounted() {
    // Try to load user_id from localStorage
    const userId = localStorage.getItem("truth_or_lie_user_id");

    if (userId) {
      // Send existing user_id to LiveView for reconnection
      this.pushEvent("set_user_id", { user_id: userId });
    }

    // Listen for save_user_id event from LiveView
    this.handleEvent("save_user_id", ({ user_id }) => {
      localStorage.setItem("truth_or_lie_user_id", user_id);
    });
  }
};
