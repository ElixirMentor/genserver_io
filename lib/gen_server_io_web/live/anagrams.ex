defmodule GenServerIoWeb.AnagramsLive do
  use GenServerIoWeb, :live_view

  alias GenServerIo.Anagrams.{Server, SessionManager, WordValidator}
  alias Phoenix.PubSub

  @impl true
  def mount(params, _session, socket) do
    case Map.get(params, "session_id") do
      nil ->
        # Home page - show game creation form
        socket =
          socket
          |> assign(:session_id, nil)
          |> assign(:language, :en)
          |> assign(:word_length_category, :medium)
          |> assign(:round_duration, 5)
          |> assign(:min_word_length, 3)
          |> assign(:target_score, 50)

        {:ok, socket}

      session_id ->
        # Game session page
        if connected?(socket) do
          PubSub.subscribe(GenServerIo.PubSub, "session:#{session_id}")
        end

        socket =
          case SessionManager.get_session(session_id) do
            {:ok, state} ->
              socket
              |> assign(:session_id, session_id)
              |> assign(:state, state)
              |> assign(:user_id, nil)
              |> assign(:nickname, "")
              |> assign(:nickname_error, nil)
              |> assign(:joined, false)
              |> assign(:word_input, "")
              |> assign(:word_error, nil)
              |> push_event("request_user_id", %{})

            {:error, :not_found} ->
              socket
              |> put_flash(:error, dgettext("anagrams", "Session not found"))
              |> push_navigate(to: ~p"/anagrams")
          end

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("user_id_received", %{"user_id" => user_id}, socket) do
    socket = assign(socket, :user_id, user_id)

    socket =
      if socket.assigns.state do
        # Check if this user_id already exists in the session
        if Map.has_key?(socket.assigns.state.players, user_id) do
          # Reconnecting player
          Server.mark_connected(socket.assigns.session_id, user_id)
          assign(socket, :joined, true)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_user_id", %{"user_id" => user_id}, socket) do
    # Alias for user_id_received - both event names supported
    handle_event("user_id_received", %{"user_id" => user_id}, socket)
  end

  @impl true
  def handle_event("set_nickname", %{"nickname" => nickname}, socket) do
    {:noreply, assign(socket, :nickname, nickname)}
  end

  @impl true
  def handle_event("join_session", %{"nickname" => nickname}, socket) do
    nickname = String.trim(nickname)

    socket =
      if nickname == "" do
        assign(socket, :nickname_error, dgettext("anagrams", "Nickname cannot be empty"))
      else
        case Server.join_session(socket.assigns.session_id, socket.assigns.user_id, nickname) do
          {:ok, _state} ->
            socket
            |> assign(:joined, true)
            |> assign(:nickname_error, nil)

          {:error, :nickname_taken} ->
            assign(socket, :nickname_error, dgettext("anagrams", "Nickname already taken"))
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_ready", %{"ready" => ready_str}, socket) do
    ready = ready_str == "true"
    Server.set_ready(socket.assigns.session_id, socket.assigns.user_id, ready)
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    Server.start_game(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("word_input_change", %{"word" => word}, socket) do
    {:noreply, assign(socket, :word_input, word)}
  end

  @impl true
  def handle_event("set_language", %{"language" => lang}, socket) do
    language_atom = String.to_existing_atom(lang)
    Gettext.put_locale(GenServerIoWeb.Gettext, lang)
    {:noreply, assign(socket, :language, language_atom)}
  end

  @impl true
  def handle_event("set_word_length", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :word_length_category, String.to_existing_atom(cat))}
  end

  @impl true
  def handle_event("set_duration", %{"duration" => duration_str}, socket) do
    {:noreply, assign(socket, :round_duration, String.to_integer(duration_str))}
  end

  @impl true
  def handle_event("set_target", %{"score" => score_str}, socket) do
    {:noreply, assign(socket, :target_score, String.to_integer(score_str))}
  end

  @impl true
  def handle_event("create_session", _params, socket) do
    config = [
      language: socket.assigns.language,
      word_length_category: socket.assigns.word_length_category,
      round_duration: socket.assigns.round_duration,
      min_word_length: socket.assigns.min_word_length,
      target_score: socket.assigns.target_score
    ]

    case SessionManager.create_session(config) do
      {:ok, session_id} ->
        {:noreply, push_navigate(socket, to: ~p"/anagrams/#{session_id}")}

      {:error, _reason} ->
        socket =
          put_flash(
            socket,
            :error,
            dgettext("anagrams", "Failed to create session. Please try again.")
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_word", %{"word" => word}, socket) do
    word = String.trim(word)

    socket =
      if word == "" do
        socket
      else
        case Server.submit_word(socket.assigns.session_id, socket.assigns.user_id, word) do
          :ok ->
            socket
            |> assign(:word_input, "")
            |> assign(:word_error, nil)

          {:error, :already_submitted} ->
            assign(socket, :word_error, dgettext("anagrams", "You already submitted this word"))

          {:error, :invalid_word} ->
            assign(socket, :word_error, dgettext("anagrams", "Invalid word"))

          {:error, _} ->
            assign(socket, :word_error, dgettext("anagrams", "Cannot submit word"))
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_word", %{"word" => word}, socket) do
    Server.remove_word(socket.assigns.session_id, socket.assigns.user_id, word)
    {:noreply, socket}
  end

  @impl true
  def handle_event("score_word", %{"word" => word, "score" => score_str}, socket) do
    score = String.to_integer(score_str)
    Server.score_word(socket.assigns.session_id, socket.assigns.user_id, word, score)
    {:noreply, socket}
  end

  @impl true
  def handle_event("next_round", _params, socket) do
    Server.next_round(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_game", _params, socket) do
    Server.new_game(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply, assign(socket, :state, state)}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:user_id] != nil and socket.assigns[:session_id] != nil do
      Server.mark_disconnected(socket.assigns.session_id, socket.assigns.user_id)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @session_id == nil do %>
        {render_home(assigns)}
      <% else %>
        <div
          phx-hook="UserIdManager"
          id="user-id-manager"
        >
          <%= if not @joined do %>
            {render_join_screen(assigns)}
          <% else %>
            <%= cond do %>
              <% @state.phase == :lobby -> %>
                {render_lobby(assigns)}
              <% @state.phase == :playing -> %>
                {render_playing(assigns)}
              <% @state.phase == :round_end -> %>
                {render_round_end(assigns)}
              <% @state.phase == :game_over -> %>
                {render_game_over(assigns)}
            <% end %>
          <% end %>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp render_home(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center p-4"
      phx-hook="SettingsLoader"
      id="settings-loader"
    >
      <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8 space-y-6">
        <div class="text-center space-y-2">
          <h1 class="text-4xl font-bold text-base-content">Anagrams</h1>
          <p class="text-base-content/70">
            Create anagrams, compete with friends, and have fun!
          </p>
        </div>

        <div class="space-y-4">
          <div>
            <label for="language-select" class="block text-sm font-medium text-base-content mb-2">
              Language
            </label>
            <select
              name="language"
              class="select select-bordered w-full"
              id="language-select"
              phx-change="set_language"
              value={@language}
            >
              <option value="en" selected={@language == :en}>English</option>
              <option value="ru" selected={@language == :ru}>Русский</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-base-content mb-2">
              Base Word Length
            </label>
            <div class="grid grid-cols-3 gap-2">
              <button
                type="button"
                phx-click="set_word_length"
                phx-value-category="short"
                class={[
                  "btn btn-sm",
                  @word_length_category == :short && "btn-primary",
                  @word_length_category != :short && "btn-outline"
                ]}
              >
                Short<br /><span class="text-xs opacity-70">(8-10)</span>
              </button>
              <button
                type="button"
                phx-click="set_word_length"
                phx-value-category="medium"
                class={[
                  "btn btn-sm",
                  @word_length_category == :medium && "btn-primary",
                  @word_length_category != :medium && "btn-outline"
                ]}
              >
                Medium<br /><span class="text-xs opacity-70">(11-13)</span>
              </button>
              <button
                type="button"
                phx-click="set_word_length"
                phx-value-category="long"
                class={[
                  "btn btn-sm",
                  @word_length_category == :long && "btn-primary",
                  @word_length_category != :long && "btn-outline"
                ]}
              >
                Long<br /><span class="text-xs opacity-70">(14+)</span>
              </button>
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium text-base-content mb-2">
              Round Duration
            </label>
            <div class="grid grid-cols-4 gap-2">
              <%= for duration <- [3, 5, 7, 10] do %>
                <button
                  type="button"
                  phx-click="set_duration"
                  phx-value-duration={duration}
                  class={[
                    "btn btn-sm",
                    @round_duration == duration && "btn-primary",
                    @round_duration != duration && "btn-outline"
                  ]}
                >
                  {duration}m
                </button>
              <% end %>
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium text-base-content mb-2">
              Target Score
            </label>
            <div class="grid grid-cols-4 gap-2">
              <%= for target <- [30, 50, 75, 100] do %>
                <button
                  type="button"
                  phx-click="set_target"
                  phx-value-score={target}
                  class={[
                    "btn btn-sm",
                    @target_score == target && "btn-primary",
                    @target_score != target && "btn-outline"
                  ]}
                >
                  {target}
                </button>
              <% end %>
            </div>
          </div>

          <button
            type="button"
            phx-click="create_session"
            class="w-full bg-gradient-to-r from-purple-600 to-pink-600 text-neutral-content font-semibold py-4 px-6 rounded-lg hover:from-purple-700 hover:to-pink-700 transition-all duration-200 transform hover:scale-105 shadow-lg"
          >
            Create New Game
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp render_join_screen(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8">
        <h1 class="text-3xl font-bold text-base-content mb-6 text-center">Join Game</h1>

        <form phx-submit="join_session" class="space-y-4">
          <div>
            <label for="nickname-input" class="block text-sm font-medium text-base-content mb-2">
              Choose your nickname
            </label>
            <input
              type="text"
              id="nickname-input"
              name="nickname"
              value={@nickname}
              phx-change="set_nickname"
              placeholder={dgettext("anagrams", "Enter your nickname")}
              class="input input-bordered input-lg w-full"
              required
              autocomplete="off"
            />
            <%= if @nickname_error do %>
              <p class="text-sm text-error mt-1">{@nickname_error}</p>
            <% end %>
          </div>

          <button type="submit" class="btn btn-primary btn-lg w-full">
            Join Game
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp render_lobby(assigns) do
    assigns = assign(assigns, :current_player, Map.get(assigns.state.players, assigns.user_id))
    assigns = assign(assigns, :all_ready, all_players_ready?(assigns.state))

    ~H"""
    <div class="container mx-auto p-4 max-w-4xl">
      <div class="card bg-base-100 shadow-2xl mt-8">
        <div class="card-body">
          <h1 class="card-title text-4xl font-bold text-center justify-center mb-2">
            Game Lobby
          </h1>

          <%!-- Session ID with Copy --%>
          <div class="text-center mb-8">
            <p class="text-base-content/70 mb-2">Session ID:</p>
            <button
              type="button"
              phx-click={JS.dispatch("phx:copy", to: "#session-url-input")}
              class="btn btn-primary btn-lg font-mono"
              title={dgettext("anagrams", "Click to copy game link")}
            >
              {@state.session_id}
            </button>
            <input
              id="session-url-input"
              type="hidden"
              value={url(~p"/anagrams/#{@state.session_id}")}
              phx-hook="CopyToClipboard"
            />
          </div>

          <%!-- Game Settings --%>
          <div class="bg-base-200 rounded-lg p-4 mb-6">
            <h3 class="font-semibold mb-2">Game Settings:</h3>
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div>Language: {language_name(@state.language)}</div>
              <div>Word Length: {category_name(@state.word_length_category)}</div>
              <div>Round Time: {@state.round_duration} minutes</div>
              <div>Target Score: {@state.target_score} points</div>
            </div>
          </div>

          <%!-- Players List --%>
          <div class="mb-6">
            <h3 class="font-semibold mb-3">
              Players ({map_size(@state.players)}):
            </h3>
            <div class="space-y-2">
              <%= for {id, player} <- @state.players do %>
                <div class="flex items-center justify-between bg-base-200 rounded-lg p-3">
                  <div class="flex items-center space-x-3">
                    <div class={[
                      "w-3 h-3 rounded-full",
                      player.connected && "bg-success",
                      not player.connected && "bg-base-300"
                    ]}>
                    </div>
                    <span class={[
                      "font-medium",
                      id == @user_id && "text-primary"
                    ]}>
                      {player.nickname}
                      <%= if id == @user_id do %>
                        <span class="badge badge-sm badge-primary ml-2">You</span>
                      <% end %>
                    </span>
                  </div>
                  <div>
                    <%= if player.ready do %>
                      <span class="badge badge-success">Ready</span>
                    <% else %>
                      <span class="badge badge-ghost">Not Ready</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Ready Button --%>
          <%= if @current_player do %>
            <div class="space-y-3">
              <%= if @current_player.ready do %>
                <button
                  type="button"
                  phx-click="set_ready"
                  phx-value-ready="false"
                  class="btn btn-neutral btn-lg w-full"
                >
                  Not Ready
                </button>
              <% else %>
                <button
                  type="button"
                  phx-click="set_ready"
                  phx-value-ready="true"
                  class="btn btn-success btn-lg w-full"
                >
                  Ready
                </button>
              <% end %>

              <%= if @all_ready do %>
                <button
                  type="button"
                  phx-click="start_game"
                  class="btn btn-primary btn-lg w-full"
                >
                  Start Game
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_playing(assigns) do
    assigns = assign(assigns, :current_player, Map.get(assigns.state.players, assigns.user_id))

    assigns =
      assign(
        assigns,
        :is_valid_input,
        WordValidator.valid_word?(
          assigns.word_input,
          assigns.state.current_base_word
        )
      )

    # Format time remaining as MM:SS
    assigns =
      assign(assigns, :formatted_time, format_time(assigns.state.time_remaining || 0))

    # Determine timer color based on time remaining
    assigns =
      assign(assigns, :timer_color, timer_color_class(assigns.state.time_remaining || 0))

    ~H"""
    <div class="container mx-auto p-4 max-w-6xl">
      <%!-- Leaderboard at top --%>
      <div class="card bg-base-100 shadow-lg mb-4">
        <div class="card-body p-4">
          <div class="flex items-center justify-between">
            <div>
              <div class="badge badge-primary badge-lg">Round {@state.round_number}</div>
            </div>
            <div class="flex items-center gap-6">
              <%!-- Timer --%>
              <div class="flex items-center gap-2">
                <.icon name="hero-clock" class={"w-5 h-5 #{@timer_color}"} />
                <span class={"font-mono text-lg font-bold #{@timer_color}"}>{@formatted_time}</span>
              </div>
              <%!-- Leaderboard scores --%>
              <div class="flex gap-4">
                <%= for {_id, player} <- Enum.take(
                      Enum.sort_by(@state.players, fn {_, p} -> -p.score end),
                      3
                    ) do %>
                  <div class="flex items-center gap-2 text-sm">
                    <span class="font-medium">{player.nickname}</span>
                    <span class="badge badge-primary font-bold">{player.score}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Main Game Area --%>
      <div class="card bg-base-100 shadow-2xl">
        <div class="card-body">
          <%!-- Base Word --%>
          <div class="bg-gradient-to-r from-blue-500 to-purple-600 text-white rounded-xl p-6 mb-6 text-center">
            <p class="text-sm mb-2">Base Word:</p>
            <p class="text-4xl md:text-5xl font-bold tracking-wider">
              {@state.current_base_word}
            </p>
          </div>

          <%!-- Word Input --%>
          <form phx-submit="submit_word" class="mb-6">
            <div class="flex gap-2">
              <div class="flex-1 relative">
                <input
                  type="text"
                  name="word"
                  value={@word_input}
                  phx-change="word_input_change"
                  placeholder={dgettext("anagrams", "Type a word...")}
                  class={[
                    "input input-bordered input-lg w-full uppercase",
                    (@word_input != "" and @is_valid_input) && "input-success",
                    (@word_input != "" and not @is_valid_input) && "input-error"
                  ]}
                />
                <%= if @word_input != "" do %>
                  <div class="absolute right-3 top-1/2 transform -translate-y-1/2">
                    <%= if @is_valid_input do %>
                      <.icon name="hero-check-circle" class="w-6 h-6 text-success" />
                    <% else %>
                      <.icon name="hero-x-circle" class="w-6 h-6 text-error" />
                    <% end %>
                  </div>
                <% end %>
              </div>
              <button type="submit" class="btn btn-primary btn-lg px-6">
                Submit
              </button>
            </div>
            <%= if @word_error do %>
              <label class="label">
                <span class="label-text-alt text-error">{@word_error}</span>
              </label>
            <% end %>
          </form>

          <%!-- Your Words --%>
          <div>
            <h3 class="font-semibold mb-3">
              Your Words
              <span class="badge badge-primary">{length(@current_player.current_round_words)}</span>
            </h3>
            <%= if @current_player.current_round_words == [] do %>
              <div class="alert">
                <span>No words submitted yet</span>
              </div>
            <% else %>
              <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
                <%= for word <- @current_player.current_round_words do %>
                  <div class="flex items-center justify-between bg-primary text-primary-content rounded-lg p-3">
                    <span class="font-medium">{word}</span>
                    <button
                      type="button"
                      phx-click="remove_word"
                      phx-value-word={word}
                      class="btn btn-ghost btn-xs btn-circle hover:bg-primary-focus"
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4" />
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_round_end(assigns) do
    # Sort words by length (longest first)
    assigns =
      assign(
        assigns,
        :sorted_submissions,
        Enum.sort_by(assigns.state.all_submissions, fn {word, _} -> -String.length(word) end)
      )

    ~H"""
    <div class="container mx-auto p-4 max-w-4xl">
      <div class="card bg-base-100 shadow-2xl mt-8">
        <div class="card-body">
          <h2 class="card-title text-3xl font-bold text-center justify-center mb-4">
            Round {@state.round_number} - Score Words
          </h2>
          <p class="text-center text-base-content/70 mb-6">
            Vote on each word: +1 (valid), 0 (skip), -1 (invalid)
          </p>

          <%!-- Word Scoring --%>
          <div class="space-y-3 mb-8">
            <%= for {word, submitters} <- @sorted_submissions do %>
              <% word_score = Map.get(@state.votes, word) %>
              <% is_voted = word_score != nil %>
              <div class="card bg-base-200 shadow">
                <div class="card-body p-4">
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <p class="text-2xl font-bold">{word}</p>
                      <p class="text-sm text-base-content/70">
                        By: {Enum.map_join(submitters, ", ", fn id -> @state.players[id].nickname end)}
                      </p>
                    </div>

                    <div class="flex gap-2">
                      <%= for {score, label, color} <- [{1, "+1", "btn-success"}, {0, "0", "btn-ghost"}, {-1, "-1", "btn-error"}] do %>
                        <% is_selected =
                          (is_voted && word_score == score) || (!is_voted && score == 1) %>
                        <button
                          type="button"
                          phx-click="score_word"
                          phx-value-word={word}
                          phx-value-score={score}
                          class={[
                            "btn btn-sm",
                            color,
                            if(is_selected,
                              do: "ring-2 ring-offset-2 ring-base-content",
                              else: "btn-outline"
                            )
                          ]}
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
                </div>
              </div>
            <% end %>
          </div>

          <button type="button" phx-click="next_round" class="btn btn-primary btn-lg w-full">
            Next Round
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp render_game_over(assigns) do
    assigns =
      assign(assigns, :winner, Map.get(assigns.state.players, assigns.state.winner_id))

    ~H"""
    <div class="container mx-auto p-4 max-w-4xl">
      <div class="card bg-base-100 shadow-2xl mt-8">
        <div class="card-body">
          <div class="text-center mb-8">
            <h2 class="text-5xl font-bold mb-4">
              Game Over!
            </h2>
            <%= if @winner do %>
              <p class="text-3xl text-primary font-bold">
                🎉 {@winner.nickname} Wins! 🎉
              </p>
              <div class="badge badge-primary badge-lg mt-4">
                Final Score: {@winner.score} points
              </div>
            <% end %>
          </div>

          <%!-- Final Leaderboard --%>
          <div class="mb-8">
            <h3 class="text-2xl font-semibold mb-4 text-center">Final Standings</h3>
            <div class="space-y-3">
              <%= for {{_id, player}, index} <- Enum.with_index(
                    Enum.sort_by(@state.players, fn {_, p} -> -p.score end),
                    1
                  ) do %>
                <div class={[
                  "card bg-base-200 shadow",
                  index == 1 && "ring-4 ring-warning",
                  index == 2 && "ring-4 ring-base-300",
                  index == 3 && "ring-4 ring-accent"
                ]}>
                  <div class="card-body p-5 flex-row justify-between items-center">
                    <div class="flex items-center space-x-4">
                      <div class={[
                        "badge badge-lg text-xl",
                        index == 1 && "badge-warning",
                        index == 2 && "badge-neutral",
                        index == 3 && "badge-accent",
                        index > 3 && "badge-ghost"
                      ]}>
                        #{index}
                      </div>
                      <span class="font-bold text-xl">{player.nickname}</span>
                    </div>
                    <span class="badge badge-primary badge-lg text-2xl font-bold">
                      {player.score}
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <button type="button" phx-click="new_game" class="btn btn-success btn-lg w-full text-lg">
            Start New Game
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp all_players_ready?(state) do
    Enum.all?(state.players, fn {_id, player} ->
      player.connected and player.ready
    end)
  end

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{pad_zero(minutes)}:#{pad_zero(remaining_seconds)}"
  end

  defp pad_zero(num) when num < 10, do: "0#{num}"
  defp pad_zero(num), do: "#{num}"

  defp timer_color_class(seconds) when seconds > 30, do: "text-success"
  defp timer_color_class(seconds) when seconds > 10, do: "text-warning"
  defp timer_color_class(_seconds), do: "text-error"

  defp language_name(:en), do: dgettext("anagrams", "English")
  defp language_name(:ru), do: "Русский"

  defp category_name(:short), do: dgettext("anagrams", "Short (8-10)")
  defp category_name(:medium), do: dgettext("anagrams", "Medium (11-13)")
  defp category_name(:long), do: dgettext("anagrams", "Long (14+)")
end
