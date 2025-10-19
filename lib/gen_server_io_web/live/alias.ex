defmodule GenServerIoWeb.AliasLive do
  use GenServerIoWeb, :live_view
  alias GenServerIo.Alias.Server

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        class="min-h-screen bg-base-200"
        id="game-container"
        phx-hook={if @session_id, do: "UserDataLoader", else: nil}
      >
        <%= if @session_id do %>
          <!-- Game Session View -->
          <%= cond do %>
            <% not @nickname_set -> %>
              <!-- Nickname Entry -->
              <div class="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 flex items-center justify-center p-4">
                <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8">
                  <h1 class="text-3xl font-bold text-base-content mb-6 text-center">
                    {dgettext("alias", "Join Game")}
                  </h1>

                  <form
                    id="nickname-form"
                    phx-submit="set_nickname"
                    phx-hook="NicknameForm"
                    class="space-y-4"
                  >
                    <div>
                      <label for="nickname-input" class="block text-sm font-medium text-base-content mb-2">
                        {dgettext("alias", "Choose your nickname")}
                      </label>
                      <input
                        type="text"
                        name="nickname"
                        value={@nickname}
                        placeholder={dgettext("alias", "Enter your nickname")}
                        class="input input-bordered input-lg w-full"
                        required
                        id="nickname-input"
                        autocomplete="off"
                      />
                    </div>

                    <button type="submit" class="btn btn-primary btn-lg w-full">
                      {dgettext("alias", "Join Game")}
                    </button>
                  </form>
                </div>
              </div>
            <% @game_state.phase == :lobby -> %>
              <!-- Lobby View -->
              <div class="container mx-auto p-4 md:p-6">
                <div class="text-center mb-8">
                  <h1 class="text-4xl font-bold mb-2">{dgettext("alias", "Alias Game Lobby")}</h1>
                  <div class="flex flex-wrap justify-center gap-2 mb-2">
                    <div class="badge badge-lg whitespace-nowrap">
                      {case Map.get(@game_state, :difficulty, :medium) do
                        :simple -> dgettext("alias", "Simple")
                        :easy -> dgettext("alias", "Easy")
                        :medium -> dgettext("alias", "Medium")
                        :difficult -> dgettext("alias", "Difficult")
                        "simple" -> dgettext("alias", "Simple")
                        "easy" -> dgettext("alias", "Easy")
                        "medium" -> dgettext("alias", "Medium")
                        "difficult" -> dgettext("alias", "Difficult")
                        _ -> dgettext("alias", "Medium")
                      end}
                    </div>
                    <div class="badge badge-lg badge-secondary whitespace-nowrap">
                      {Map.get(@game_state, :target_score, 30)} {dgettext("alias", "Points")}
                    </div>
                    <div class="badge badge-lg badge-accent whitespace-nowrap">
                      {case Map.get(@game_state, :language, :en) do
                        :en -> "English"
                        :ru -> "Русский"
                        "en" -> "English"
                        "ru" -> "Русский"
                        _ -> "English"
                      end}
                    </div>
                  </div>
                  <div class="text-sm opacity-75 mt-2 px-4">
                    <div class="mb-1">{dgettext("alias", "Share this link:")}</div>
                    <div class="flex justify-center">
                      <button
                        class="bg-base-300 hover:bg-base-content hover:text-base-300 px-3 py-2 rounded break-all text-xs sm:text-sm transition-colors cursor-pointer border-0 font-mono text-center max-w-xs"
                        phx-click="copy_share_link"
                        title={dgettext("alias", "Click to copy")}
                        id="share-link-btn"
                        data-session-id={@session_id}
                      >
                        <span id="share-url-text">/{@session_id}</span>
                      </button>
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 md:gap-6">
                  <!-- Teams -->
                  <div class="card bg-base-100 shadow-xl">
                    <div class="card-body">
                      <h2 class="card-title">{dgettext("alias", "Teams")}</h2>

                      <%= for team <- Map.get(@game_state, :teams, []) do %>
                        <div class="border rounded-lg p-4 mb-4">
                          <div class="flex justify-between items-center mb-2">
                            <h3 class="font-bold">{team.name}</h3>
                            <div class="badge">{dgettext("alias", "Score:")} {team.score}</div>
                          </div>

                          <div class="flex flex-wrap gap-2 mb-3">
                            <%= for member_id <- team.members do %>
                              <% player =
                                Map.get(@game_state, :players, %{})
                                |> Map.get(member_id, %{nickname: dgettext("alias", "Unknown"), ready: false}) %>
                              <% designated_explainer =
                                if @game_state.current_explainer &&
                                     Map.has_key?(@game_state.players, @game_state.current_explainer) do
                                  @game_state.current_explainer
                                else
                                  # Find first member from first team who actually exists
                                  first_team = List.first(Map.get(@game_state, :teams, []))

                                  if first_team do
                                    Enum.find(
                                      first_team.members,
                                      &Map.has_key?(@game_state.players, &1)
                                    )
                                  else
                                    nil
                                  end
                                end %>
                              <% is_first_explainer = member_id == designated_explainer %>
                              <div class={[
                                "badge",
                                if(player.ready, do: "badge-success", else: "badge-outline")
                              ]}>
                                <%= if is_first_explainer do %>
                                  →
                                <% end %>
                                {player.nickname}
                                <% total_points = Map.get(player, :total_points, 0) %>
                                <%= if total_points > 0 do %>
                                  <span class="ml-1 font-bold">({total_points})</span>
                                <% end %>
                                <%= if player.ready do %>
                                  <.icon name="hero-check" class="w-3 h-3 ml-1" />
                                <% else %>
                                  <span class="opacity-60"></span>
                                <% end %>
                              </div>
                            <% end %>
                          </div>

                          <% current_player_data =
                            if @session_id && @user_id,
                              do: Map.get(@game_state.players || %{}, @user_id),
                              else: nil %>
                          <%= unless @game_state.phase == :playing do %>
                            <%= if (current_player_data || %{team: nil}).team == team.name do %>
                              <button
                                phx-click="leave_team"
                                class="btn btn-sm btn-error btn-outline"
                              >
                                {dgettext("alias", "Leave Team")}
                              </button>
                            <% else %>
                              <button
                                phx-click="join_team"
                                phx-value-team={team.name}
                                class="btn btn-sm btn-outline"
                              >
                                {dgettext("alias", "Join Team")}
                              </button>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>

                      <div class="flex gap-2">
                        <%= unless @game_state.phase == :playing do %>
                          <button phx-click="join_team" phx-value-team="new" class="btn btn-primary">
                            <.icon name="hero-plus" class="w-4 h-4" /> {dgettext("alias", "Create New Team")}
                          </button>
                        <% else %>
                          <div class="alert alert-info">
                            <.icon name="hero-information-circle" class="w-6 h-6" />
                            <span>{dgettext("alias", "Team changes are locked during gameplay")}</span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                  
    <!-- Waiting Room -->
                  <div class="card bg-base-100 shadow-xl">
                    <div class="card-body">
                      <h2 class="card-title">{dgettext("alias", "Waiting Room")}</h2>

                      <div class="flex flex-wrap gap-2">
                        <%= for {player_id, player} <- Map.get(@game_state, :players, %{}) do %>
                          <%= if player.team == nil do %>
                            <div class="badge badge-ghost">
                              {player.nickname}
                              <% total_points = Map.get(player, :total_points, 0) %>
                              <%= if total_points > 0 do %>
                                <span class="ml-1 font-bold">({total_points})</span>
                              <% end %>
                            </div>
                          <% end %>
                        <% end %>
                      </div>

                      <div class="divider"></div>

                      <div class="space-y-4">
                        <% player =
                          if @session_id && @user_id,
                            do: Map.get(@game_state.players || %{}, @user_id),
                            else: nil %>

                        <%= if player && player.team do %>
                          <button
                            phx-click="toggle_ready"
                            class={[
                              "btn w-full",
                              if(player.ready,
                                do: "btn-success",
                                else: "btn-primary"
                              )
                            ]}
                          >
                            <%= if player.ready do %>
                              <.icon name="hero-check" class="w-5 h-5" /> {dgettext("alias", "Ready")}!
                            <% else %>
                              {dgettext("alias", "Ready")}?
                            <% end %>
                          </button>

                          <%= if can_start_game?(Map.get(@game_state, :teams, []), Map.get(@game_state, :players, %{})) do %>
                            <% designated_first_explainer =
                              if @game_state.current_explainer &&
                                   Map.has_key?(@game_state.players, @game_state.current_explainer) do
                                @game_state.current_explainer
                              else
                                first_team = List.first(@game_state.teams)

                                if first_team && length(first_team.members) > 0,
                                  do:
                                    Enum.find(
                                      first_team.members,
                                      &Map.has_key?(@game_state.players, &1)
                                    ),
                                  else: nil
                              end %>

                            <% current_player_data = Map.get(@game_state.players || %{}, @user_id) %>
                            <% can_user_start =
                              @user_id == designated_first_explainer ||
                                (!designated_first_explainer && current_player_data &&
                                   current_player_data.team && current_player_data.ready) %>

                            <%= if can_user_start do %>
                              <button phx-click="start_game" class="btn btn-accent w-full">
                                <.icon name="hero-play" class="w-5 h-5" /> {dgettext("alias", "Start Game")}
                              </button>
                            <% else %>
                              <div class="text-sm opacity-75 text-center">
                                <%= if designated_first_explainer do %>
                                  <% first_explainer =
                                    Map.get(@game_state.players, designated_first_explainer) %>
                                  <%= if first_explainer do %>
                                    {dgettext("alias", "Waiting for %{name} to start the game",
                                      name: first_explainer.nickname
                                    )}
                                  <% else %>
                                    {dgettext("alias", "Any ready player can start the game")}
                                  <% end %>
                                <% else %>
                                  {dgettext("alias", "Any ready player can start the game")}
                                <% end %>
                              </div>
                            <% end %>
                          <% else %>
                            <div class="text-sm opacity-75 text-center">
                              {dgettext("alias", "Need at least 2 players in teams, all ready")}
                            </div>
                          <% end %>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% Map.get(@game_state, :phase) == :playing -> %>
              <!-- Playing View -->
              <div class="container mx-auto p-4 md:p-6">
                <div class="text-center mb-6">
                  <h1 class="text-3xl font-bold mb-2">{dgettext("alias", "Round in Progress")}</h1>

                  <div class="stats shadow mb-4">
                    <div class="stat">
                      <div class="stat-title">{dgettext("alias", "Current Team")}</div>
                      <div class="stat-value text-lg">
                        {dgettext("alias", "Team %{number}", number: Map.get(@game_state, :current_team, 0) + 1)}
                      </div>
                    </div>
                    <div class="stat">
                      <div class="stat-title">{dgettext("alias", "Time Left")}</div>
                      <div class={[
                        "stat-value text-2xl",
                        time_class(Map.get(@game_state, :time_remaining, 0) || 0)
                      ]}>
                        {format_time(Map.get(@game_state, :time_remaining, 0) || 0)}
                      </div>
                    </div>
                  </div>
                </div>
                
    <!-- Team Scores -->
                <div class="flex justify-center mb-6">
                  <div class="flex gap-4">
                    <%= for {team, idx} <- Enum.with_index(@game_state.teams) do %>
                      <div class={[
                        "badge badge-lg",
                        if(idx == @game_state.current_team, do: "badge-primary", else: "badge-ghost")
                      ]}>
                        Team {idx + 1}: {team.score}
                      </div>
                    <% end %>
                  </div>
                </div>

                <% # Check if user can explain - either they're the designated explainer or the explainer is missing and they're on the team %>
                <% explainer_exists = Map.has_key?(@game_state.players, @game_state.current_explainer) %>
                <% current_player = Map.get(@game_state.players, @user_id) %>
                <% current_team =
                  if @game_state.current_team,
                    do: Enum.at(@game_state.teams, @game_state.current_team),
                    else: nil %>
                <% user_on_explaining_team =
                  current_team && current_player && Enum.member?(current_team.members, @user_id) %>
                <% can_explain =
                  @game_state.current_explainer == @user_id ||
                    (!explainer_exists && user_on_explaining_team) %>

                <%= if can_explain do %>
                  <!-- Explainer View -->
                  <div class="card bg-base-100 shadow-xl">
                    <div class="card-body text-center">
                      <h2 class="card-title justify-center">{dgettext("alias", "You're explaining!")}</h2>

                      <%= if @game_state.current_word do %>
                        <div class="bg-primary text-primary-content p-8 rounded-lg mb-6">
                          <div class={[
                            "font-bold break-all",
                            cond do
                              String.length(@game_state.current_word) > 15 ->
                                "text-2xl sm:text-3xl md:text-4xl"

                              String.length(@game_state.current_word) > 10 ->
                                "text-3xl sm:text-4xl md:text-5xl"

                              String.length(@game_state.current_word) > 7 ->
                                "text-4xl sm:text-5xl md:text-6xl"

                              true ->
                                "text-5xl sm:text-6xl"
                            end
                          ]}>
                            {@game_state.current_word}
                          </div>
                        </div>

                        <%= if (@game_state.time_remaining || 0) > 0 do %>
                          <div class="flex justify-center">
                            <button
                              phx-click="next_word"
                              phx-value-action="next"
                              class="btn btn-primary btn-lg"
                            >
                              <.icon name="hero-arrow-right" class="w-6 h-6" /> {dgettext("alias", "Next")}
                            </button>
                          </div>
                        <% else %>
                          <div class="alert alert-error">
                            <.icon name="hero-clock" class="w-6 h-6" />
                            <span>{dgettext("alias", "Time's up!")}</span>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <!-- Observer View -->
                  <div class="card bg-base-100 shadow-xl">
                    <div class="card-body text-center">
                      <h2 class="card-title justify-center">
                        {Map.get(@game_state.players, @game_state.current_explainer, %{
                          nickname: dgettext("alias", "Unknown")
                        }).nickname} {dgettext("alias", "is explaining")}
                      </h2>
                      <div class="text-lg opacity-75 mb-4">
                        {dgettext("alias", "Listen and guess the words!")}
                      </div>

                      <%= if @game_state.current_word do %>
                        <div class="bg-base-300 text-base-content p-6 rounded-lg mb-4">
                          <div class="text-2xl font-bold">🤫</div>
                          <div class="text-sm opacity-75 mt-2">
                            {dgettext("alias", "Word hidden - listen to the explanation!")}
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
    <!-- Words Used This Round -->
                <%= if length(@game_state.words_used) > 0 do %>
                  <div class="card bg-base-100 shadow-xl mt-6">
                    <div class="card-body text-center">
                      <h3 class="card-title justify-center">{dgettext("alias", "Words This Round")}</h3>
                      <div class="flex flex-col items-center gap-2 mt-4">
                        <%= for word_data <- Enum.reverse(@game_state.words_used) do %>
                          <div class="text-lg font-medium">
                            {word_data.word}
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% @game_state.phase == :round_end -> %>
              <!-- Round End / Scoring View -->
              <div class="container mx-auto p-4 md:p-6">
                <div class="text-center mb-6">
                  <h1 class="text-3xl font-bold mb-2">{dgettext("alias", "Round Complete")}</h1>
                  <div class="text-lg">{dgettext("alias", "Score the words from this round")}</div>
                </div>
                
    <!-- Team Scores -->
                <div class="flex justify-center mb-6">
                  <div class="flex gap-4">
                    <%= for {team, idx} <- Enum.with_index(@game_state.teams) do %>
                      <div class={[
                        "badge badge-lg",
                        if(idx == @game_state.current_team, do: "badge-primary", else: "badge-ghost")
                      ]}>
                        Team {idx + 1}: {team.score}
                      </div>
                    <% end %>
                  </div>
                </div>
                
    <!-- Word Scoring -->
                <div class="card bg-base-100 shadow-xl mb-6 max-w-2xl mx-auto">
                  <div class="card-body">
                    <h3 class="card-title justify-center">{dgettext("alias", "Score Words")}</h3>

                    <div class="space-y-3 mt-4">
                      <%= for {word_data, reverse_index} <- Enum.with_index(Enum.reverse(@game_state.words_used)) do %>
                        <% actual_index = length(@game_state.words_used) - 1 - reverse_index %>
                        <div class="flex items-center justify-between p-3 border rounded-lg">
                          <div class="flex-1 text-center">
                            <span class="font-semibold text-lg">{word_data.word}</span>
                          </div>

                          <div class="flex gap-2">
                            <%= for {score, label, color} <- [{1, "+1", "btn-success"}, {0, "0", "btn-ghost"}, {-1, "-1", "btn-error"}] do %>
                              <% is_selected = Map.get(word_data, :score) == score %>
                              <button
                                phx-click="score_word"
                                phx-value-index={actual_index}
                                phx-value-score={score}
                                class={[
                                  "btn btn-sm",
                                  color,
                                  if(is_selected,
                                    do: "ring-2 ring-offset-2 ring-base-content",
                                    else: "btn-outline"
                                  )
                                ]}
                                title="Click to mark word as {label}"
                              >
                                <%= if is_selected do %>
                                  ✓ {label}
                                <% else %>
                                  {label}
                                <% end %>
                              </button>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>

                    <div class="card-actions justify-center mt-6">
                      <button phx-click="next_round" class="btn btn-primary btn-lg">
                        {dgettext("alias", "Next Round")} <.icon name="hero-arrow-right" class="w-5 h-5" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% @game_state.phase == :game_over -> %>
              <!-- Game Over View -->
              <div class="container mx-auto p-4 md:p-6">
                <div class="text-center mb-6">
                  <h1 class="text-4xl font-bold mb-4">{dgettext("alias", "Game Over!")}</h1>

                  <div class="card bg-base-100 shadow-xl">
                    <div class="card-body">
                      <h2 class="card-title justify-center">{dgettext("alias", "Final Scores")}</h2>

                      <div class="space-y-2">
                        <%= for team <- Enum.sort_by(@game_state.teams, & &1.score, :desc) do %>
                          <div class={[
                            "flex justify-between items-center p-4 rounded-lg",
                            if(team.score >= @game_state.target_score,
                              do: "bg-success text-success-content",
                              else: "bg-base-200"
                            )
                          ]}>
                            <div class="font-bold text-lg">
                              Team {Enum.find_index(@game_state.teams, &(&1 == team)) + 1}
                            </div>
                            <div class="text-2xl font-bold">{team.score}</div>
                          </div>
                        <% end %>
                      </div>

                      <div class="card-actions justify-center mt-6">
                        <button phx-click="start_new_game" class="btn btn-primary btn-lg">
                          Play Again <.icon name="hero-arrow-path" class="w-5 h-5" />
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
          <% end %>
        <% else %>
          <!-- Home Screen -->
          <div
            class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center p-4"
            phx-hook="SettingsLoader"
            id="settings-loader"
          >
            <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8 space-y-6">
              <div class="text-center space-y-2">
                <h1 class="text-4xl font-bold text-base-content">{dgettext("alias", "Alias")}</h1>
                <p class="text-base-content/70">
                  {dgettext("alias", "Create a game session and invite your friends to play!")}
                </p>
              </div>

              <form phx-submit="create_session" id="game-settings-form" class="space-y-4">
                <div>
                  <label
                    for="difficulty-select"
                    class="block text-sm font-medium text-base-content mb-2"
                  >
                    {dgettext("alias", "Choose difficulty")}
                  </label>
                  <select
                    name="difficulty"
                    class="select select-bordered w-full"
                    id="difficulty-select"
                    phx-change="change_difficulty"
                    value={@difficulty}
                  >
                    <option value="simple" selected={@difficulty == :simple}>
                      {dgettext("alias", "Simple")}
                    </option>
                    <option value="easy" selected={@difficulty == :easy}>{dgettext("alias", "Easy")}</option>
                    <option value="medium" selected={@difficulty == :medium}>
                      {dgettext("alias", "Medium")}
                    </option>
                    <option value="difficult" selected={@difficulty == :difficult}>
                      {dgettext("alias", "Difficult")}
                    </option>
                  </select>
                </div>

                <div>
                  <label
                    for="target-score-select"
                    class="block text-sm font-medium text-base-content mb-2"
                  >
                    {dgettext("alias", "Points to win")}
                  </label>
                  <select
                    name="target-score"
                    class="select select-bordered w-full"
                    id="target-score-select"
                    phx-change="change_target_score"
                    value={@target_score}
                  >
                    <option value="10" selected={@target_score == 10}>
                      10 {dgettext("alias", "Points")}
                    </option>
                    <option value="15" selected={@target_score == 15}>
                      15 {dgettext("alias", "Points")}
                    </option>
                    <option value="20" selected={@target_score == 20}>
                      20 {dgettext("alias", "Points")}
                    </option>
                    <option value="30" selected={@target_score == 30}>
                      30 {dgettext("alias", "Points")}
                    </option>
                    <option value="50" selected={@target_score == 50}>
                      50 {dgettext("alias", "Points")}
                    </option>
                    <option value="100" selected={@target_score == 100}>
                      100 {dgettext("alias", "Points")}
                    </option>
                  </select>
                </div>

                <div>
                  <label
                    for="language-select"
                    class="block text-sm font-medium text-base-content mb-2"
                  >
                    {dgettext("alias", "Language")}
                  </label>
                  <select
                    name="language"
                    class="select select-bordered w-full"
                    id="language-select"
                    phx-change="change_language"
                    value={@language}
                  >
                    <option value="en" selected={@language == :en}>English</option>
                    <option value="ru" selected={@language == :ru}>Русский</option>
                  </select>
                </div>

                <button
                  type="submit"
                  class="w-full bg-gradient-to-r from-purple-600 to-pink-600 text-neutral-content font-semibold py-4 px-6 rounded-lg hover:from-purple-700 hover:to-pink-700 transition-all duration-200 transform hover:scale-105 shadow-lg"
                >
                  {dgettext("alias", "Create New Game")}
                </button>
              </form>

              <div class="pt-4 border-t border-base-300 text-center">
                <p class="text-sm text-base-content/60">
                  Made with ❤️ by
                  <a
                    href="https://1703.lu"
                    class="hover:text-base-content/80 transition-opacity"
                  >
                    1703.lu
                  </a>
                </p>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Timer Sound Effect -->
        <%= if @timer_sound do %>
          <audio autoplay>
            <source src="/sounds/timer_end.mp3" type="audio/mpeg" />
          </audio>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    case Map.get(params, "session_id") do
      nil ->
        # Home page
        # Set default locale
        Gettext.put_locale(GenServerIoWeb.Gettext, "en")

        socket_with_assigns =
          assign(socket,
            difficulty: :medium,
            language: :en,
            locale: "en",
            target_score: 30,
            session_id: nil,
            creating_session: false,
            timer_sound: false,
            nickname_set: false,
            game_state: %{teams: [], players: %{}, phase: :lobby}
          )

        {:ok, socket_with_assigns}

      session_id ->
        # Game session page
        # Generate a new user_id for now, will be replaced if we get one from sessionStorage
        user_id = generate_user_id()

        case Server.get_state(session_id) do
          {:ok, state} ->
            Phoenix.PubSub.subscribe(GenServerIo.PubSub, "game:#{session_id}")

            # Set locale based on game language
            game_language = Map.get(state, :language, :en)

            locale =
              case game_language do
                :en -> "en"
                :ru -> "ru"
                "en" -> "en"
                "ru" -> "ru"
                _ -> "en"
              end

            Gettext.put_locale(GenServerIoWeb.Gettext, locale)

            final_socket =
              assign(socket,
                session_id: session_id,
                user_id: user_id,
                game_state: state,
                nickname: "",
                nickname_set: false,
                timer_sound: false,
                difficulty: state.difficulty,
                language: game_language,
                locale: locale,
                creating_session: false
              )

            {:ok, final_socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, dgettext("alias", "Game session not found"))
             |> push_navigate(to: ~p"/alias")}
        end
    end
  end

  @impl true
  def handle_event(
        "restore_session",
        %{"user_id" => stored_user_id, "nickname" => nickname},
        socket
      ) do
    IO.inspect(
      {:restore_session_called, stored_user_id, nickname, session_id: socket.assigns.session_id},
      label: "RESTORE_SESSION_DEBUG"
    )

    # Use the stored user_id if available, check if this user is still in the game
    if socket.assigns.session_id do
      {:ok, game_state} = Server.get_state(socket.assigns.session_id)

      IO.inspect({:game_state_players, Map.keys(game_state.players)},
        label: "RESTORE_SESSION_DEBUG"
      )

      IO.inspect(
        {:looking_for_user, stored_user_id,
         found: Map.has_key?(game_state.players, stored_user_id)},
        label: "RESTORE_SESSION_DEBUG"
      )

      # Check if the stored user still exists in the game
      if Map.has_key?(game_state.players, stored_user_id) do
        IO.inspect(:user_found_in_game, label: "RESTORE_SESSION_DEBUG")
        # User still exists, restore their session
        player = Map.get(game_state.players, stored_user_id)

        # Always rejoin the team if they had one, regardless of connected status
        restored_state =
          if player.team do
            case Server.rejoin_team(socket.assigns.session_id, stored_user_id, player.team) do
              {:ok, state} ->
                state

              _ ->
                # If rejoin fails, mark them as connected anyway
                case Server.mark_connected(socket.assigns.session_id, stored_user_id) do
                  {:ok, state} -> state
                  _ -> game_state
                end
            end
          else
            # No team, just mark as connected
            case Server.mark_connected(socket.assigns.session_id, stored_user_id) do
              {:ok, state} -> state
              _ -> game_state
            end
          end

        updated_socket =
          socket
          |> assign(:user_id, stored_user_id)
          |> assign(:nickname, player.nickname)
          |> assign(:nickname_set, true)
          |> assign(:game_state, restored_state)

        {:noreply, updated_socket}
      else
        # User doesn't exist anymore but we have a nickname, try to join
        IO.inspect(:user_not_found_trying_nickname, label: "RESTORE_SESSION_DEBUG")

        if nickname && String.trim(nickname) != "" do
          # Check if nickname is taken by someone else (not including disconnected players)
          case Server.check_nickname_availability(
                 socket.assigns.session_id,
                 String.trim(nickname)
               ) do
            :available ->
              case Server.join_session(
                     socket.assigns.session_id,
                     socket.assigns.user_id,
                     String.trim(nickname)
                   ) do
                {:ok, state} ->
                  updated_socket =
                    socket
                    |> assign(:nickname, String.trim(nickname))
                    |> assign(:nickname_set, true)
                    |> assign(:game_state, state)
                    |> push_event("save-user-id", %{user_id: socket.assigns.user_id})

                  {:noreply, updated_socket}

                {:error, _} ->
                  # Join failed, show nickname form
                  {:noreply, socket}
              end

            :taken_by_connected ->
              # Nickname truly taken by active player, show form
              {:noreply, socket}

            :taken_by_disconnected ->
              # Nickname taken by disconnected player, we can reclaim it
              case Server.reclaim_nickname(
                     socket.assigns.session_id,
                     socket.assigns.user_id,
                     String.trim(nickname)
                   ) do
                {:ok, state} ->
                  updated_socket =
                    socket
                    |> assign(:nickname, String.trim(nickname))
                    |> assign(:nickname_set, true)
                    |> assign(:game_state, state)
                    |> push_event("save-user-id", %{user_id: socket.assigns.user_id})

                  {:noreply, updated_socket}

                {:error, _} ->
                  {:noreply, socket}
              end
          end
        else
          {:noreply, socket}
        end
      end
    else
      IO.inspect(:no_session_id, label: "RESTORE_SESSION_DEBUG")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("try_auto_join", %{"nickname" => nickname}, socket) do
    # Only attempt auto-join if nickname is not already set and we're in a game session
    if !socket.assigns.nickname_set && socket.assigns.session_id do
      case Server.join_session(
             socket.assigns.session_id,
             socket.assigns.user_id,
             String.trim(nickname)
           ) do
        {:ok, state} ->
          updated_socket =
            socket
            |> assign(:nickname, String.trim(nickname))
            |> assign(:nickname_set, true)
            |> assign(:game_state, state)

          {:noreply, updated_socket}

        {:error, :nickname_taken} ->
          # If nickname is taken, just proceed with normal flow (show nickname form)
          {:noreply, socket}

        {:error, _reason} ->
          # For any other error, proceed with normal flow
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    # Convert language to locale string
    locale =
      case language do
        "ru" -> "ru"
        "en" -> "en"
        _ -> "en"
      end

    # Set the locale for gettext for this process
    Gettext.put_locale(GenServerIoWeb.Gettext, locale)

    # Update socket assigns and force a re-render
    updated_socket =
      socket
      |> assign(:language, String.to_atom(language))
      |> assign(:locale, locale)
      |> push_event("save-language", %{language: language})

    # The LiveView will re-render with the new locale automatically
    {:noreply, updated_socket}
  end

  @impl true
  def handle_event("change_difficulty", %{"difficulty" => difficulty}, socket) do
    # Update socket assigns and save to sessionStorage
    updated_socket =
      socket
      |> assign(:difficulty, String.to_atom(difficulty))
      |> push_event("save-difficulty", %{difficulty: difficulty})

    {:noreply, updated_socket}
  end

  @impl true
  def handle_event("change_target_score", %{"target-score" => target_score}, socket) do
    # Update socket assigns and save to sessionStorage
    updated_socket =
      socket
      |> assign(:target_score, String.to_integer(target_score))
      |> push_event("save-target-score", %{target_score: target_score})

    {:noreply, updated_socket}
  end

  @impl true
  def handle_event(
        "restore_saved_settings",
        %{"language" => language, "difficulty" => difficulty, "target_score" => target_score},
        socket
      ) do
    # Only restore settings on home page
    if socket.assigns.session_id == nil do
      # Convert language to locale string and atom
      locale =
        case language do
          "ru" -> "ru"
          "en" -> "en"
          _ -> "en"
        end

      language_atom = String.to_atom(language)
      difficulty_atom = String.to_atom(difficulty)
      target_score_int = String.to_integer(target_score)

      # Set the locale for gettext for this process
      Gettext.put_locale(GenServerIoWeb.Gettext, locale)

      # Update socket assigns
      updated_socket =
        socket
        |> assign(:language, language_atom)
        |> assign(:locale, locale)
        |> assign(:difficulty, difficulty_atom)
        |> assign(:target_score, target_score_int)

      {:noreply, updated_socket}
    else
      {:noreply, socket}
    end
  end

  # Fallback when no saved settings are found
  @impl true
  def handle_event("restore_saved_settings", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_share_link", _params, socket) do
    if socket.assigns.session_id do
      updated_socket =
        socket
        |> push_event("copy-share-link", %{
          url: "/#{socket.assigns.session_id}",
          message: dgettext("alias", "Game URL copied to clipboard!")
        })

      {:noreply, updated_socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "create_session",
        %{"difficulty" => difficulty, "target-score" => target_score, "language" => language},
        socket
      ) do
    session_id = generate_session_id()
    difficulty_atom = String.to_atom(difficulty)
    target_score_int = String.to_integer(target_score)
    language_atom = String.to_atom(language)

    case Server.create_session(session_id, difficulty_atom, target_score_int, language_atom) do
      {:ok, _session_id} ->
        updated_socket =
          socket
          |> push_event("save-game-settings", %{
            difficulty: difficulty,
            target_score: target_score
          })
          |> push_event("save-language", %{language: language})
          |> push_event("copy-game-url", %{
            url: "/#{session_id}",
            message: dgettext("alias", "Game URL copied to clipboard!")
          })
          |> push_navigate(to: ~p"/alias/#{session_id}")

        {:noreply, updated_socket}
    end
  end

  # Fallback for when language is not provided (backwards compatibility)
  @impl true
  def handle_event(
        "create_session",
        %{"difficulty" => difficulty, "target-score" => target_score},
        socket
      ) do
    session_id = generate_session_id()
    difficulty_atom = String.to_atom(difficulty)
    target_score_int = String.to_integer(target_score)

    case Server.create_session(session_id, difficulty_atom, target_score_int, :en) do
      {:ok, _session_id} ->
        updated_socket =
          socket
          |> push_event("copy-game-url", %{
            url: "/#{session_id}",
            message: dgettext("alias", "Game URL copied to clipboard!")
          })
          |> push_navigate(to: ~p"/alias/#{session_id}")

        {:noreply, updated_socket}
    end
  end

  @impl true
  def handle_event("set_nickname", %{"nickname" => nickname}, socket) do
    IO.inspect(
      {:set_nickname_start,
       session_id: socket.assigns.session_id, user_id: socket.assigns.user_id},
      label: "SET_NICKNAME_DEBUG"
    )

    if String.length(String.trim(nickname)) > 0 do
      case Server.join_session(
             socket.assigns.session_id,
             socket.assigns.user_id,
             String.trim(nickname)
           ) do
        {:ok, state} ->
          updated_socket =
            socket
            |> assign(:nickname, String.trim(nickname))
            |> assign(:nickname_set, true)
            |> assign(:game_state, state)
            |> push_event("save-nickname", %{nickname: String.trim(nickname)})
            |> push_event("save-user-id", %{user_id: socket.assigns.user_id})

          IO.inspect(
            {:set_nickname_after,
             session_id: updated_socket.assigns.session_id,
             user_id: updated_socket.assigns.user_id},
            label: "SET_NICKNAME_DEBUG"
          )

          {:noreply, updated_socket}

        {:error, :nickname_taken} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("alias", "This nickname is already taken. Please choose a different one.")
           )}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("alias", "Failed to join session"))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("alias", "Please enter a valid nickname"))}
    end
  end

  @impl true
  def handle_event("join_team", %{"team" => team_name}, socket) do
    case Server.join_team(socket.assigns.session_id, socket.assigns.user_id, team_name) do
      {:ok, state} ->
        {:noreply, assign(socket, game_state: state)}

      {:error, :no_team_changes_during_play} ->
        {:noreply,
         put_flash(socket, :error, dgettext("alias", "Cannot change teams during active gameplay"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join team")}
    end
  end

  @impl true
  def handle_event("leave_team", _params, socket) do
    case Server.leave_team(socket.assigns.session_id, socket.assigns.user_id) do
      {:ok, state} ->
        {:noreply, assign(socket, game_state: state)}

      {:error, :no_team_changes_during_play} ->
        {:noreply,
         put_flash(socket, :error, dgettext("alias", "Cannot change teams during active gameplay"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to leave team")}
    end
  end

  @impl true
  def handle_event("toggle_ready", _params, socket) do
    current_ready = get_player_ready_status(socket)

    IO.inspect(
      {:toggle_ready_debug,
       session_id: socket.assigns.session_id,
       user_id: socket.assigns.user_id,
       current_ready: current_ready,
       new_ready: !current_ready},
      label: "TOGGLE_READY_DEBUG"
    )

    case Server.set_ready(socket.assigns.session_id, socket.assigns.user_id, !current_ready) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update ready status")}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case Server.start_game(socket.assigns.session_id, socket.assigns.user_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, :not_first_explainer} ->
        {:noreply, put_flash(socket, :error, "Only the first explainer can start the game")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start game")}
    end
  end

  @impl true
  def handle_event("next_word", %{"action" => action}, socket) do
    action_atom = String.to_atom(action)

    IO.inspect(
      {:next_word_debug,
       session_id: socket.assigns.session_id, user_id: socket.assigns.user_id, action: action_atom},
      label: "NEXT_WORD_DEBUG"
    )

    case Server.next_word(socket.assigns.session_id, socket.assigns.user_id, action_atom) do
      {:ok, _state} ->
        IO.inspect({:next_word_success, action: action_atom}, label: "NEXT_WORD_DEBUG")
        {:noreply, socket}

      {:error, reason} ->
        IO.inspect({:next_word_error, reason: reason, action: action_atom},
          label: "NEXT_WORD_DEBUG"
        )

        {:noreply, put_flash(socket, :error, "Cannot perform action")}
    end
  end

  @impl true
  def handle_event("score_word", %{"index" => index, "score" => score}, socket) do
    {index_int, ""} = Integer.parse(index)
    {score_int, ""} = Integer.parse(score)

    case Server.score_word(socket.assigns.session_id, index_int, score_int) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to score word")}
    end
  end

  @impl true
  def handle_event("next_round", _params, socket) do
    case Server.next_round(socket.assigns.session_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, :no_teams} ->
        # If no teams available, redirect to home to create a new session
        {:noreply, push_navigate(socket, to: ~p"/alias")}

      {:error, reason} ->
        IO.inspect({:next_round_error, reason: reason}, label: "NEXT_ROUND_DEBUG")

        error_message =
          case reason do
            :not_round_end -> "Can only start next round from round end"
            :no_current_team -> "No current team found"
            _ -> "Failed to start next round: #{inspect(reason)}"
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  @impl true
  def handle_event("start_new_game", _params, socket) do
    # Reset the game to lobby phase
    case Server.reset_to_lobby(socket.assigns.session_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        IO.inspect({:reset_game_error, reason: reason}, label: "RESET_GAME_DEBUG")
        {:noreply, put_flash(socket, :error, "Failed to start new game")}
    end
  end

  @impl true
  def handle_info({:game_update, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info(:timer_finished, socket) do
    {:noreply, assign(socket, timer_sound: true)}
  end

  @impl true
  def terminate(_reason, socket) do
    # Clean up: remove user from game session if they disconnect
    if Map.get(socket.assigns, :session_id) && Map.get(socket.assigns, :user_id) do
      Server.leave_session(socket.assigns.session_id, socket.assigns.user_id)
    end

    :ok
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64() |> String.slice(0, 8)
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64()
  end

  defp get_player_ready_status(socket) do
    game_state = Map.get(socket.assigns, :game_state, %{players: %{}})
    user_id = Map.get(socket.assigns, :user_id)

    case Map.get(game_state.players, user_id) do
      %{ready: ready} -> ready
      _ -> false
    end
  end

  defp can_start_game?(teams, players) do
    teams_with_members = Enum.filter(teams, &(length(&1.members) > 0))
    team_members = teams |> Enum.flat_map(& &1.members) |> MapSet.new()
    total_team_members = teams_with_members |> Enum.map(&length(&1.members)) |> Enum.sum()

    ready_statuses =
      team_members
      |> Enum.map(fn user_id ->
        case Map.get(players, user_id) do
          %{ready: ready, nickname: nickname} -> {nickname, ready}
          _ -> {"unknown", false}
        end
      end)

    all_ready =
      team_members
      |> Enum.all?(fn user_id ->
        case Map.get(players, user_id) do
          %{ready: true} -> true
          _ -> false
        end
      end)

    can_start = length(teams_with_members) >= 1 and total_team_members >= 2 and all_ready

    IO.inspect(
      {:can_start_game_debug,
       teams_count: length(teams_with_members),
       total_members: total_team_members,
       ready_statuses: ready_statuses,
       all_ready: all_ready,
       can_start: can_start},
      label: "CAN_START_GAME_DEBUG"
    )

    can_start
  end

  defp time_class(time) do
    cond do
      time > 30 -> "text-green-500"
      time > 10 -> "text-yellow-500"
      true -> "text-red-500"
    end
  end

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
end
