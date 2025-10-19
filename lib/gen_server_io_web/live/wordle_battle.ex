defmodule GenServerIoWeb.WordleBattleLive do
  use GenServerIoWeb, :live_view
  alias GenServerIo.WordleBattle.Server

  @impl true
  def mount(params, _session, socket) do
    case Map.get(params, "session_id") do
      nil ->
        # Home page: show game creation form
        {:ok,
         assign(socket,
           session_id: nil,
           duration: 3,
           language: :en
         )}

      session_id ->
        # Game session: connect to game and subscribe to updates
        if Server.session_exists?(session_id) do
          Phoenix.PubSub.subscribe(GenServerIo.PubSub, "game:#{session_id}")

          {:ok, state} = Server.get_state(session_id)
          user_id = generate_user_id()

          {:ok,
           assign(socket,
             session_id: session_id,
             user_id: user_id,
             game_state: state,
             nickname: "",
             nickname_set: false,
             guess: "",
             guess_error: nil
           )}
        else
          {:ok,
           socket
           |> put_flash(:error, dgettext("wordle_battle", "Session not found"))
           |> push_navigate(to: ~p"/wordle_battle")}
        end
    end
  end

  @impl true
  def handle_event("create_session", %{"duration" => duration, "language" => language}, socket) do
    session_id = generate_session_id()
    duration_int = String.to_integer(duration)
    language_atom = String.to_atom(language)

    Server.create_session(session_id, duration_int, language_atom)

    {:noreply, push_navigate(socket, to: ~p"/wordle_battle/#{session_id}")}
  end

  @impl true
  def handle_event("set_nickname", %{"nickname" => nickname}, socket) do
    case Server.join_session(socket.assigns.session_id, socket.assigns.user_id, nickname) do
      {:ok, state} ->
        # Save to localStorage via hook
        {:noreply,
         socket
         |> assign(nickname_set: true, game_state: state, nickname: nickname)
         |> push_event("save_user_data", %{user_id: socket.assigns.user_id, nickname: nickname})}

      {:error, :nickname_taken} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("wordle_battle", "Nickname already taken"))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("wordle_battle", "Failed to join session"))}
    end
  end

  @impl true
  def handle_event("restore_session", %{"user_id" => user_id, "nickname" => nickname}, socket) do
    # User reconnected with stored credentials
    if socket.assigns.session_id && Server.session_exists?(socket.assigns.session_id) do
      case Server.mark_connected(socket.assigns.session_id, user_id) do
        {:ok, state} ->
          {:noreply,
           assign(socket,
             user_id: user_id,
             nickname: nickname,
             nickname_set: true,
             game_state: state
           )}

        {:error, _} ->
          # User not in this session, need to rejoin
          {:noreply, assign(socket, user_id: user_id, nickname: nickname)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_ready", _, socket) do
    player = Map.get(socket.assigns.game_state.players, socket.assigns.user_id)

    if player do
      {:ok, state} =
        Server.set_ready(
          socket.assigns.session_id,
          socket.assigns.user_id,
          not player.ready
        )

      {:noreply, assign(socket, game_state: state)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_game", _, socket) do
    case Server.start_game(socket.assigns.session_id) do
      {:ok, state} ->
        {:noreply, assign(socket, game_state: state)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_guess", %{"guess" => guess}, socket) do
    case Server.submit_guess(socket.assigns.session_id, socket.assigns.user_id, guess) do
      {:ok, state} ->
        {:noreply, assign(socket, game_state: state, guess: "", guess_error: nil)}

      {:error, :invalid_length} ->
        {:noreply,
         assign(socket, guess_error: dgettext("wordle_battle", "Must be exactly 5 letters"))}

      {:error, :invalid_word} ->
        {:noreply, assign(socket, guess_error: dgettext("wordle_battle", "Not in word list"))}

      {:error, _reason} ->
        {:noreply, assign(socket, guess_error: dgettext("wordle_battle", "Invalid guess"))}
    end
  end

  @impl true
  def handle_event("update_guess", %{"guess" => guess}, socket) do
    {:noreply, assign(socket, guess: String.upcase(guess), guess_error: nil)}
  end

  @impl true
  def handle_event("new_game", _, socket) do
    case Server.new_game(socket.assigns.session_id) do
      {:ok, state} ->
        {:noreply, assign(socket, game_state: state)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_duration", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, duration: String.to_integer(duration))}
  end

  @impl true
  def handle_event("update_language", %{"language" => language}, socket) do
    {:noreply, assign(socket, language: String.to_atom(language))}
  end

  @impl true
  def handle_info({:game_update, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:time_update, time_remaining}, socket) do
    state = %{socket.assigns.game_state | time_remaining: time_remaining}
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session_id] && socket.assigns[:user_id] && socket.assigns[:nickname_set] do
      Server.mark_disconnected(socket.assigns.session_id, socket.assigns.user_id)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        class="min-h-screen bg-base-200"
        id="game-container"
        phx-hook={if @session_id, do: "WordleBattleUserDataLoader", else: nil}
      >
        <%= if @session_id do %>
          <%!-- Game Session View --%>
          <%= cond do %>
            <% not @nickname_set -> %>
              <.render_nickname_entry {assigns} />
            <% @game_state.phase == :lobby -> %>
              <.render_lobby {assigns} />
            <% @game_state.phase == :playing -> %>
              <.render_playing {assigns} />
            <% @game_state.phase == :game_over -> %>
              <.render_game_over {assigns} />
          <% end %>
        <% else %>
          <%!-- Create Session View --%>
          <.render_create_session {assigns} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp render_create_session(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 to-pink-50 dark:from-gray-900 dark:to-gray-800 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8">
        <h1 class="text-4xl font-bold text-base-content mb-2 text-center">
          {dgettext("wordle_battle", "Wordle Battle")}
        </h1>
        <p class="text-base-content/70 text-center mb-8">
          {dgettext("wordle_battle", "Competitive word-guessing game")}
        </p>

        <form
          phx-submit="create_session"
          class="space-y-6"
          id="settings-form"
          phx-hook="WordleBattleSettingsLoader"
        >
          <div>
            <label class="block text-sm font-medium text-base-content mb-2">
              {dgettext("wordle_battle", "Game Duration")}
            </label>
            <select name="duration" class="select select-bordered w-full" phx-change="update_duration">
              <option value="1" selected={@duration == 1}>
                {dgettext("wordle_battle", "1 minute")}
              </option>
              <option value="3" selected={@duration == 3}>
                {dgettext("wordle_battle", "3 minutes")}
              </option>
              <option value="5" selected={@duration == 5}>
                {dgettext("wordle_battle", "5 minutes")}
              </option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-base-content mb-2">
              {dgettext("wordle_battle", "Language")}
            </label>
            <select name="language" class="select select-bordered w-full" phx-change="update_language">
              <option value="en" selected={@language == :en}>
                English
              </option>
              <option value="ru" selected={@language == :ru}>
                Русский
              </option>
            </select>
          </div>

          <button type="submit" class="btn btn-primary btn-lg w-full">
            {dgettext("wordle_battle", "Create Game")}
          </button>
        </form>

        <div class="mt-8 p-4 bg-info/10 rounded-lg">
          <h3 class="font-semibold text-base-content mb-2">
            {dgettext("wordle_battle", "How to Play")}
          </h3>
          <ul class="text-sm text-base-content/80 space-y-1">
            <li>• {dgettext("wordle_battle", "Guess 5-letter words in 6 tries")}</li>
            <li>• {dgettext("wordle_battle", "Race against other players")}</li>
            <li>• {dgettext("wordle_battle", "Earn points for quick guesses")}</li>
            <li>• {dgettext("wordle_battle", "Highest score wins!")}</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp render_nickname_entry(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 to-pink-50 dark:from-gray-900 dark:to-gray-800 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8">
        <h1 class="text-3xl font-bold text-base-content mb-6 text-center">
          {dgettext("wordle_battle", "Join Game")}
        </h1>

        <form
          id="nickname-form"
          phx-submit="set_nickname"
          phx-hook="WordleBattleNicknameForm"
          class="space-y-4"
        >
          <div>
            <label for="nickname-input" class="block text-sm font-medium text-base-content mb-2">
              {dgettext("wordle_battle", "Choose your nickname")}
            </label>
            <input
              type="text"
              name="nickname"
              value={@nickname}
              placeholder={dgettext("wordle_battle", "Enter your nickname")}
              class="input input-bordered input-lg w-full"
              required
              id="nickname-input"
              autocomplete="off"
              maxlength="20"
            />
          </div>

          <button type="submit" class="btn btn-primary btn-lg w-full">
            {dgettext("wordle_battle", "Join Game")}
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp render_lobby(assigns) do
    ~H"""
    <div class="container mx-auto p-4 md:p-6">
      <div class="text-center mb-8">
        <h1 class="text-4xl font-bold mb-2">{dgettext("wordle_battle", "Wordle Battle Lobby")}</h1>
        <div class="flex flex-wrap justify-center gap-2 mb-2">
          <div class="badge badge-lg">
            {dgettext("wordle_battle", "Duration:")} {@game_state.session_duration} {dgettext(
              "wordle_battle",
              "min"
            )}
          </div>
          <div class="badge badge-lg badge-accent">
            {case @game_state.language do
              :en -> "English"
              :ru -> "Русский"
              _ -> "English"
            end}
          </div>
        </div>
        <div class="text-sm opacity-75 mt-2">
          {dgettext("wordle_battle", "Share this link:")}{" "}
          <code class="bg-base-300 px-2 py-1 rounded">/{@session_id}</code>
        </div>
      </div>

      <div class="max-w-2xl mx-auto">
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">{dgettext("wordle_battle", "Players")}</h2>

            <div class="space-y-2">
              <%= for {_id, player} <- @game_state.players do %>
                <div class="flex items-center justify-between p-3 bg-base-200 rounded">
                  <span class="font-medium">{player.nickname}</span>
                  <div class={[
                    "badge",
                    if(player.ready, do: "badge-success", else: "badge-warning")
                  ]}>
                    {if player.ready,
                      do: dgettext("wordle_battle", "Ready"),
                      else: dgettext("wordle_battle", "Not Ready")}
                  </div>
                </div>
              <% end %>

              <%= if map_size(@game_state.players) == 0 do %>
                <p class="text-center text-base-content/50 py-4">
                  {dgettext("wordle_battle", "Waiting for players...")}
                </p>
              <% end %>
            </div>
          </div>
        </div>

        <%= if Map.has_key?(@game_state.players, @user_id) do %>
          <div class="space-y-3">
            <button
              type="button"
              phx-click="toggle_ready"
              class={[
                "btn btn-lg w-full",
                if(get_in(@game_state.players, [@user_id, :ready]),
                  do: "btn-warning",
                  else: "btn-success"
                )
              ]}
            >
              {if get_in(@game_state.players, [@user_id, :ready]),
                do: dgettext("wordle_battle", "Not Ready"),
                else: dgettext("wordle_battle", "Ready")}
            </button>

            <%= if map_size(@game_state.players) > 0 and Enum.all?(@game_state.players, fn {_id, p} -> p.ready end) do %>
              <button type="button" phx-click="start_game" class="btn btn-primary btn-lg w-full">
                {dgettext("wordle_battle", "Start Game")}
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_playing(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-4 max-w-6xl">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="lg:col-span-2">
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="flex justify-between items-center mb-6">
                <h1 class="text-2xl font-bold">{dgettext("wordle_battle", "Wordle Battle")}</h1>
                <div class={[
                  "text-3xl font-bold px-4 py-2 rounded",
                  time_class(@game_state.time_remaining)
                ]}>
                  {format_time(@game_state.time_remaining)}
                </div>
              </div>

              <%= if Map.has_key?(@game_state.players, @user_id) do %>
                <%= with player <- @game_state.players[@user_id],
                       true <- player.current_word != nil do %>
                  <div>
                    <p class="text-sm text-base-content/70 mb-3">
                      {dgettext("wordle_battle", "Attempt")} {length(player.current_attempts) + 1}/6 | {dgettext(
                        "wordle_battle",
                        "Score:"
                      )} {player.score} | {dgettext("wordle_battle", "Words:")} {player.words_guessed}
                    </p>

                    <div class="space-y-2 mb-4">
                      <%= for attempt <- player.current_attempts do %>
                        <div class="flex gap-2 justify-center sm:justify-start">
                          <%= for {letter, result} <- Enum.zip(
                                String.graphemes(attempt.guess),
                                attempt.result
                              ) do %>
                            <div class={[
                              "w-12 h-12 sm:w-14 sm:h-14 flex items-center justify-center rounded font-bold text-white text-xl",
                              letter_color(result)
                            ]}>
                              {letter}
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Empty rows --%>
                      <%= for _ <- (length(player.current_attempts) + 1)..6 do %>
                        <div class="flex gap-2 justify-center sm:justify-start">
                          <%= for _ <- 1..5 do %>
                            <div class="w-12 h-12 sm:w-14 sm:h-14 border-2 border-base-300 rounded">
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <form phx-submit="submit_guess" phx-change="update_guess" id="guess-form">
                      <div class="flex gap-2">
                        <input
                          type="text"
                          name="guess"
                          value={@guess}
                          maxlength="5"
                          placeholder={dgettext("wordle_battle", "Enter guess")}
                          class="input input-bordered flex-1 uppercase text-xl font-bold"
                          phx-hook="WordleBattleGuessInput"
                          id="guess-input"
                        />
                        <button type="submit" class="btn btn-primary">
                          {dgettext("wordle_battle", "Submit")}
                        </button>
                      </div>
                      <%= if @guess_error do %>
                        <p class="text-error text-sm mt-2">{@guess_error}</p>
                      <% end %>
                    </form>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>

        <div class="lg:col-span-1">
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="text-xl font-bold mb-4">{dgettext("wordle_battle", "Leaderboard")}</h2>
              <div class="space-y-3">
                <%= for {_id, player} <- Enum.sort_by(@game_state.players, fn {_, p} -> -p.score end) do %>
                  <div class="flex justify-between items-center p-3 bg-base-200 rounded">
                    <div>
                      <p class="font-semibold">{player.nickname}</p>
                      <p class="text-sm text-base-content/70">
                        {player.words_guessed} {dgettext("wordle_battle", "words")}
                      </p>
                    </div>
                    <p class="text-2xl font-bold text-primary">{player.score}</p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_game_over(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-2xl">
      <div class="card bg-base-100 shadow-2xl">
        <div class="card-body p-8">
          <h1 class="text-4xl font-bold text-center mb-6">
            {dgettext("wordle_battle", "Game Over!")}
          </h1>

          <%= if @game_state.winner_id && @game_state.final_rankings != [] do %>
            <div class="mb-8 p-6 bg-gradient-to-r from-yellow-400 to-amber-500 rounded-lg text-center shadow-lg">
              <p class="text-sm font-semibold text-yellow-950 uppercase tracking-wide mb-2">
                {dgettext("wordle_battle", "Winner")}
              </p>
              <p class="text-3xl font-bold text-yellow-950">
                {Enum.at(@game_state.final_rankings, 0).nickname}
              </p>
              <p class="text-xl font-bold text-yellow-950 mt-2">
                {Enum.at(@game_state.final_rankings, 0).score} {dgettext("wordle_battle", "points")}
              </p>
            </div>
          <% end %>

          <div class="mb-8">
            <h2 class="text-xl font-semibold mb-4">{dgettext("wordle_battle", "Final Rankings")}</h2>
            <div class="space-y-2">
              <%= for {ranking, index} <- Enum.with_index(@game_state.final_rankings, 1) do %>
                <div class="flex justify-between items-center p-4 bg-base-200 rounded">
                  <div class="flex items-center gap-3">
                    <span class="text-2xl font-bold text-base-content/60">#{index}</span>
                    <div>
                      <p class="font-semibold text-base-content">{ranking.nickname}</p>
                      <p class="text-sm text-base-content/80">
                        {dgettext("wordle_battle", "Avg:")} {:erlang.float_to_binary(
                          ranking.avg_attempts / 1,
                          decimals: 2
                        )} {dgettext("wordle_battle", "attempts")}
                      </p>
                    </div>
                  </div>
                  <p class="text-2xl font-bold text-primary">{ranking.score}</p>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex gap-3">
            <button
              type="button"
              phx-click="new_game"
              class="btn btn-success flex-1"
            >
              {dgettext("wordle_battle", "New Game")}
            </button>
            <.link
              navigate={~p"/wordle_battle"}
              class="btn btn-neutral flex-1"
            >
              {dgettext("wordle_battle", "Home")}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp time_class(seconds) when seconds > 60, do: "bg-success/20 text-success-content"
  defp time_class(seconds) when seconds > 30, do: "bg-warning/20 text-warning-content"
  defp time_class(_), do: "bg-error/20 text-error-content"

  defp letter_color(:correct), do: "bg-success"
  defp letter_color(:present), do: "bg-warning"
  defp letter_color(:wrong), do: "bg-neutral"

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
