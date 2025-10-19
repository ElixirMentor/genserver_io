defmodule GenServerIoWeb.TruthOrLieLive do
  @moduledoc """
  LiveView for the Truth or Lie game, handling both home screen and game session.
  """

  use GenServerIoWeb, :live_view

  alias GenServerIo.TruthOrLie.Server

  @impl true
  def mount(params, _session, socket) do
    case Map.get(params, "session_id") do
      nil ->
        # Home page
        {:ok,
         assign(socket,
           target_score: 15,
           language: :en,
           session_id: nil,
           user_id: nil,
           nickname: nil,
           joined: false,
           state: nil,
           time_remaining: nil
         )}

      session_id ->
        # Ensure session exists
        case ensure_session_exists(session_id) do
          :ok ->
            # Generate user_id (will be replaced if found in localStorage)
            user_id = generate_user_id()

            if connected?(socket) do
              # Subscribe to session updates
              Phoenix.PubSub.subscribe(GenServerIo.PubSub, "session:#{session_id}")

              # Load initial state
              state = Server.get_state(session_id)

              {:ok,
               assign(socket,
                 session_id: session_id,
                 user_id: user_id,
                 nickname: nil,
                 joined: false,
                 state: state,
                 time_remaining: nil
               )}
            else
              {:ok,
               assign(socket,
                 session_id: session_id,
                 user_id: user_id,
                 nickname: nil,
                 joined: false,
                 state: nil,
                 time_remaining: nil
               )}
            end

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, dgettext("truth_or_lie", "Game session not found"))
             |> push_navigate(to: ~p"/truth_or_lie")}
        end
    end
  end

  @impl true
  def handle_event("create_session", %{"target_score" => target_score_str}, socket) do
    target_score = String.to_integer(target_score_str)
    session_id = generate_session_id()

    case start_session(session_id, target_score) do
      {:ok, _pid} ->
        {:noreply, push_navigate(socket, to: ~p"/truth_or_lie/#{session_id}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("truth_or_lie", "Failed to create session. Please try again.")
         )
         |> push_navigate(to: ~p"/truth_or_lie")}
    end
  end

  @impl true
  def handle_event("set_user_id", %{"user_id" => user_id}, socket) do
    # Received from JS hook after reading localStorage
    socket = assign(socket, user_id: user_id)

    # Check if user is already in the session
    if socket.assigns.state do
      if Map.has_key?(socket.assigns.state.players, user_id) do
        player = socket.assigns.state.players[user_id]
        Server.mark_connected(socket.assigns.session_id, user_id)

        socket =
          socket
          |> assign(:nickname, player.nickname)
          |> assign(:joined, true)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("join_session", %{"nickname" => nickname}, socket) do
    case Server.join_session(socket.assigns.session_id, socket.assigns.user_id, nickname) do
      {:ok, _state} ->
        socket =
          socket
          |> assign(:nickname, nickname)
          |> assign(:joined, true)
          |> push_event("save_user_id", %{user_id: socket.assigns.user_id})

        {:noreply, socket}

      {:error, :nickname_taken} ->
        {:noreply, put_flash(socket, :error, dgettext("truth_or_lie", "Nickname already taken"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("truth_or_lie", "Failed to join session"))}
    end
  end

  @impl true
  def handle_event("toggle_ready", _params, socket) do
    if socket.assigns.joined and socket.assigns.state do
      player = socket.assigns.state.players[socket.assigns.user_id]
      new_ready = not player.ready

      Server.set_ready(socket.assigns.session_id, socket.assigns.user_id, new_ready)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    Server.start_game(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_question", params, socket) do
    question_data = %{
      "text" => params["question_text"],
      "answers" => [
        %{"text" => params["answer_a"], "is_truth" => params["truth"] == "A"},
        %{"text" => params["answer_b"], "is_truth" => params["truth"] == "B"},
        %{"text" => params["answer_c"], "is_truth" => params["truth"] == "C"}
      ]
    }

    Server.submit_question(socket.assigns.session_id, socket.assigns.user_id, question_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_guess", %{"guess" => guess}, socket) do
    Server.submit_guess(socket.assigns.session_id, socket.assigns.user_id, guess)
    {:noreply, socket}
  end

  @impl true
  def handle_event("continue", _params, socket) do
    Server.continue(socket.assigns.session_id)
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
    {:noreply, assign(socket, state: state)}
  end

  @impl true
  def handle_info({:timer_update, time_remaining}, socket) do
    {:noreply, assign(socket, time_remaining: time_remaining)}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session_id] && socket.assigns[:user_id] && socket.assigns[:joined] do
      Server.leave_session(socket.assigns.session_id, socket.assigns.user_id)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @session_id do %>
        <!-- Game Session View -->
        <div
          id="game-container"
          class="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50"
          phx-hook="UserIdManager"
        >
          <%= if @joined and @state do %>
            {render_phase(assigns)}
          <% else %>
            {render_join_screen(assigns)}
          <% end %>
        </div>
      <% else %>
        <!-- Home Screen -->
        {render_home_screen(assigns)}
      <% end %>
    </Layouts.app>
    """
  end

  defp render_home_screen(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-base-100 rounded-2xl shadow-2xl p-8 space-y-6">
        <div class="text-center space-y-2">
          <h1 class="text-4xl font-bold text-base-content">Truth or Lie</h1>
          <p class="text-base-content/70">
            A social deduction game where you create questions with one truth and two lies!
          </p>
        </div>

        <form phx-submit="create_session" class="space-y-4">
          <div>
            <label for="language-select" class="block text-sm font-medium text-base-content mb-2">
              Language
            </label>
            <select
              name="language"
              class="select select-bordered w-full"
              id="language-select"
              value={@language}
            >
              <option value="en" selected>English</option>
            </select>
          </div>

          <div>
            <label for="target-score" class="block text-sm font-medium text-base-content mb-2">
              Target Score
            </label>
            <select
              id="target-score"
              name="target_score"
              class="select select-bordered w-full"
            >
              <option value="5">5 points</option>
              <option value="10">10 points</option>
              <option value="15" selected>15 points</option>
              <option value="20">20 points</option>
              <option value="25">25 points</option>
              <option value="30">30 points</option>
            </select>
          </div>

          <button
            type="submit"
            class="w-full bg-gradient-to-r from-purple-600 to-pink-600 text-neutral-content font-semibold py-4 px-6 rounded-lg hover:from-purple-700 hover:to-pink-700 transition-all duration-200 transform hover:scale-105 shadow-lg"
          >
            Create New Game
          </button>
        </form>

        <div class="pt-4 border-t border-base-300">
          <h2 class="text-lg font-semibold text-base-content mb-2">How to Play</h2>
          <ul class="text-sm text-base-content/70 space-y-1">
            <li>• Create questions about yourself</li>
            <li>• Add one true answer and two lies</li>
            <li>• Guess the truth in others' questions</li>
            <li>• First to reach the target score wins!</li>
          </ul>
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

        <form id="join-form" phx-submit="join_session" class="space-y-4">
          <div>
            <label for="nickname" class="block text-sm font-medium text-base-content mb-2">
              Choose your nickname
            </label>
            <input
              type="text"
              id="nickname"
              name="nickname"
              required
              autocomplete="off"
              class="input input-bordered input-lg w-full"
              placeholder={dgettext("truth_or_lie", "Enter your nickname")}
            />
          </div>

          <button type="submit" class="btn btn-primary btn-lg w-full">
            Join Game
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp render_phase(assigns) do
    case assigns.state.phase do
      :lobby -> render_lobby(assigns)
      :creating -> render_creating(assigns)
      :guessing -> render_guessing(assigns)
      :results -> render_results(assigns)
      :round_end -> render_round_end(assigns)
      :game_over -> render_game_over(assigns)
    end
  end

  defp render_lobby(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8 space-y-6">
        <div class="text-center">
          <h1 class="text-4xl font-bold text-base-content mb-2">Truth or Lie</h1>
          <p class="text-base-content/70">
            Room Code: <span class="font-mono font-bold">{@session_id}</span>
          </p>
          <p class="text-base-content/70">Target Score: {@state.target_score} points</p>
          <p class="text-base-content/70">Round: {@state.round_number}</p>
        </div>

        <div>
          <h2 class="text-xl font-semibold mb-4 text-base-content">
            Players ({map_size(@state.players)})
          </h2>
          <div class="space-y-2">
            <div
              :for={{user_id, player} <- @state.players}
              class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
            >
              <div class="flex items-center gap-3">
                <span class="text-lg">{if player.connected, do: "🟢", else: "🔴"}</span>
                <span class="font-medium text-base-content">
                  {player.nickname}
                  {if user_id == @user_id, do: dgettext("truth_or_lie", " (You)")}
                </span>
              </div>
              <div class="flex items-center gap-4">
                <span class="text-base-content/70">Score: {player.total_score}</span>
                <span class={[
                  "badge",
                  if(player.ready, do: "badge-success", else: "badge-ghost")
                ]}>
                  {if player.ready,
                    do: dgettext("truth_or_lie", "Ready"),
                    else: dgettext("truth_or_lie", "Not Ready")}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex gap-4">
          <button
            type="button"
            phx-click="toggle_ready"
            class={[
              "btn flex-1",
              if(get_in(@state.players, [@user_id, :ready]), do: "btn-ghost", else: "btn-info")
            ]}
          >
            {if get_in(@state.players, [@user_id, :ready]),
              do: dgettext("truth_or_lie", "Not Ready"),
              else: dgettext("truth_or_lie", "Ready")}
          </button>

          <%= if all_ready?(@state) and can_start?(@state) do %>
            <button
              type="button"
              phx-click="start_game"
              class="btn btn-success flex-1"
            >
              Start Game
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_creating(assigns) do
    assigns =
      assigns
      |> assign(:time, assigns.time_remaining || assigns.state.time_remaining)
      |> assign(:player_ready, get_in(assigns.state.players, [assigns.user_id, :ready]) || false)
      |> assign(
        :formatted_time,
        format_time(assigns.time_remaining || assigns.state.time_remaining)
      )

    ~H"""
    <div class="max-w-3xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-2xl font-bold text-base-content">Create Your Question</h2>
          <div class="text-xl font-mono font-bold text-primary">
            {@formatted_time}
          </div>
        </div>

        <%= if @player_ready do %>
          <div class="alert alert-success">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div>
              <div class="font-bold">Question Submitted!</div>
              <div class="text-sm">Waiting for other players...</div>
            </div>
          </div>
        <% else %>
          <form id="question-form" phx-submit="submit_question" phx-update="ignore" class="space-y-6">
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">
                Write a question about yourself:
              </label>
              <textarea
                id="question-text"
                name="question_text"
                rows="3"
                required
                class="textarea textarea-bordered w-full"
                placeholder={dgettext("truth_or_lie", "What is my favorite hobby?")}
              />
            </div>

            <div class="space-y-4">
              <div :for={label <- ["A", "B", "C"]} class="space-y-2">
                <label class="block text-sm font-medium text-base-content">
                  Answer {label}:
                </label>
                <input
                  type="text"
                  name={"answer_#{String.downcase(label)}"}
                  required
                  class="input input-bordered w-full"
                  placeholder={dgettext("truth_or_lie", "Enter answer")}
                />
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="radio" name="truth" value={label} required class="radio radio-primary" />
                  <span class="text-sm text-base-content/70">This is the TRUTH</span>
                </label>
              </div>
            </div>

            <button type="submit" class="btn btn-primary w-full">
              Submit & Ready
            </button>
          </form>
        <% end %>

        <div class="mt-6 pt-6 border-t border-base-300">
          <p class="text-sm text-base-content/70 mb-2">Other players:</p>
          <div class="flex flex-wrap gap-2">
            <span
              :for={{user_id, player} <- @state.players}
              :if={user_id != @user_id and player.connected}
              class={["badge", if(player.ready, do: "badge-success", else: "badge-ghost")]}
            >
              {player.nickname} {if player.ready, do: "✓"}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_guessing(assigns) do
    assigns =
      assigns
      |> assign(:time, assigns.time_remaining || assigns.state.time_remaining)
      |> assign(:author_id, get_current_author(assigns.state))
      |> assign(:question, get_current_question(assigns.state))
      |> assign(:is_author, get_current_author(assigns.state) == assigns.user_id)
      |> assign(
        :formatted_time,
        format_time(assigns.time_remaining || assigns.state.time_remaining)
      )

    ~H"""
    <div class="max-w-3xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-2xl font-bold text-base-content">
            {if @is_author,
              do: dgettext("truth_or_lie", "Your Question"),
              else: "#{get_in(@state.players, [@author_id, :nickname])}'s Question"}
          </h2>
          <div class="text-xl font-mono font-bold text-primary">
            {@formatted_time}
          </div>
        </div>

        <div class="mb-8">
          <p class="text-xl text-base-content mb-6">
            {@question.text || dgettext("truth_or_lie", "No question provided")}
          </p>

          <%= if @is_author do %>
            <div class="space-y-3">
              <div
                :for={answer <- @question.answers}
                class="p-4 bg-base-200 rounded-lg flex items-center justify-between"
              >
                <span class="text-base-content">{answer.label}) {answer.text}</span>
                <span class={[
                  "badge",
                  if(answer.is_truth, do: "badge-success", else: "badge-error")
                ]}>
                  {if answer.is_truth,
                    do: dgettext("truth_or_lie", "✓ TRUTH"),
                    else: dgettext("truth_or_lie", "✗ LIE")}
                </span>
              </div>
            </div>

            <p class="text-center text-base-content/70 mt-6">👀 Watching others guess...</p>
          <% else %>
            <form id="guess-form" phx-submit="submit_guess" phx-update="ignore" class="space-y-3">
              <div :for={answer <- @question.answers} class="relative">
                <input
                  type="radio"
                  id={"guess-#{answer.label}"}
                  name="guess"
                  value={answer.label}
                  required
                  class="peer sr-only"
                />
                <label
                  for={"guess-#{answer.label}"}
                  class="block p-4 border-2 border-base-300 rounded-lg cursor-pointer hover:bg-base-200 peer-checked:border-primary peer-checked:bg-primary/10 transition"
                >
                  {answer.label}) {answer.text}
                </label>
              </div>

              <button type="submit" class="btn btn-primary w-full mt-4">
                Submit & Ready
              </button>
            </form>
          <% end %>
        </div>

        <div class="pt-6 border-t border-base-300">
          <p class="text-sm text-base-content/70 mb-2">Players:</p>
          <div class="flex flex-wrap gap-2">
            <span
              :for={{user_id, player} <- @state.players}
              :if={user_id != @author_id and player.connected}
              class={["badge", if(player.ready, do: "badge-success", else: "badge-ghost")]}
            >
              {player.nickname} {if player.ready, do: "✓"}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_results(assigns) do
    assigns =
      assigns
      |> assign(:results, assigns.state.current_results)
      |> assign(:author, assigns.state.players[assigns.state.current_results.question_author])

    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8">
        <h2 class="text-2xl font-bold text-base-content mb-6">
          Results - {@author.nickname}'s Question
        </h2>

        <div class="mb-8">
          <p class="text-xl text-base-content mb-4">
            {get_in(@state.players, [@results.question_author, :question, :text])}
          </p>

          <div class="space-y-3">
            <div
              :for={answer <- get_in(@state.players, [@results.question_author, :question, :answers])}
              class={[
                "p-4 rounded-lg flex items-center justify-between",
                if(answer.label == @results.correct_answer,
                  do: "bg-success/20 border-2 border-success",
                  else: "bg-base-200"
                )
              ]}
            >
              <span class="font-medium text-base-content">
                {answer.label}) {answer.text}
              </span>
              <%= if answer.label == @results.correct_answer do %>
                <span class="badge badge-success">
                  ✓ TRUTH
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <div class="mb-8">
          <h3 class="text-lg font-semibold text-base-content mb-4">Who guessed what:</h3>
          <div class="space-y-2">
            <div
              :for={{player_id, guess} <- @results.player_guesses}
              class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
            >
              <div class="flex items-center gap-3">
                <span class="text-base-content">
                  {get_in(@state.players, [player_id, :nickname])}
                </span>
                <span class="text-base-content/70">
                  → {guess.guess || dgettext("truth_or_lie", "No answer")}
                </span>
              </div>
              <div class="flex items-center gap-3">
                <span class="font-medium">
                  {if guess.correct,
                    do: dgettext("truth_or_lie", "✅ Correct!"),
                    else: dgettext("truth_or_lie", "❌ Wrong")}
                </span>
                <span class="text-base-content/70">
                  {if guess.points_awarded > 0, do: "+#{guess.points_awarded} point"}
                </span>
              </div>
            </div>
          </div>

          <div class="mt-4 p-4 bg-primary/20 rounded-lg">
            <p class="font-medium text-base-content">
              <%= if @results.author_points > 0 do %>
                🎉 {@author.nickname} (author): FOOLED EVERYONE! +{@results.author_points} points
              <% else %>
                🎭 {@author.nickname} (author): Someone guessed it! 0 points
              <% end %>
            </p>
          </div>
        </div>

        <div class="mb-6">
          <h3 class="text-lg font-semibold text-base-content mb-4">Current Scores:</h3>
          <div class="space-y-2">
            <div
              :for={{user_id, player} <- sort_by_score(@state.players)}
              class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
            >
              <span class="font-medium text-base-content">{player.nickname}</span>
              <span class="text-lg font-bold text-primary">{player.total_score} points</span>
            </div>
          </div>
        </div>

        <button type="button" phx-click="continue" class="btn btn-primary w-full">
          Continue to Next Question
        </button>
      </div>
    </div>
    """
  end

  defp render_round_end(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8">
        <h2 class="text-3xl font-bold text-base-content mb-6 text-center">
          🏁 Round {@state.round_number} Complete
        </h2>

        <div class="mb-8">
          <h3 class="text-xl font-semibold text-base-content mb-4">
            Scores after Round {@state.round_number}:
          </h3>
          <div class="space-y-3">
            <div
              :for={{user_id, player} <- sort_by_score(@state.players)}
              class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
            >
              <div>
                <span class="font-medium text-lg text-base-content">{player.nickname}</span>
                <span class="text-base-content/70 ml-2">
                  (needs {max(0, @state.target_score - player.total_score)} more)
                </span>
              </div>
              <span class="text-2xl font-bold text-primary">{player.total_score} points</span>
            </div>
          </div>

          <p class="text-center text-base-content/70 mt-4">
            Target: First to {@state.target_score} points wins!
          </p>
        </div>

        <button type="button" phx-click="next_round" class="btn btn-primary w-full">
          Start Next Round
        </button>
      </div>
    </div>
    """
  end

  defp render_game_over(assigns) do
    assigns = assign(assigns, :winner, assigns.state.players[assigns.state.winner_id])

    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="bg-base-100 rounded-xl shadow-lg p-8">
        <h2 class="text-4xl font-bold text-base-content mb-6 text-center">🏆 GAME OVER</h2>

        <div class="text-center mb-8 p-6 bg-warning/30 rounded-lg border-2 border-warning">
          <p class="text-2xl font-bold text-base-content mb-2">👑 WINNER: {@winner.nickname}!</p>
          <p class="text-xl text-base-content">Final Score: {@winner.total_score} points</p>
          <div class="mt-4 text-sm text-base-content/70">
            <p>Correct Guesses: {@winner.correct_guesses}</p>
            <p>Perfect Deceptions: {@winner.times_fooled_everyone}</p>
          </div>
        </div>

        <div class="mb-8">
          <h3 class="text-xl font-semibold text-base-content mb-4">Final Rankings:</h3>
          <div class="space-y-2">
            <div
              :for={{user_id, player} <- sort_by_score(@state.players)}
              class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
            >
              <div>
                <span class="font-medium text-lg text-base-content">{player.nickname}</span>
                <span class="text-sm text-base-content/70 ml-2">
                  ({player.correct_guesses} correct, {player.times_fooled_everyone}x fooled)
                </span>
              </div>
              <span class="text-xl font-bold text-primary">{player.total_score} points</span>
            </div>
          </div>
        </div>

        <div class="flex gap-4">
          <button type="button" phx-click="new_game" class="btn btn-success flex-1">
            Start New Game
          </button>
          <a href={~p"/truth_or_lie"} class="btn btn-ghost flex-1">
            Home
          </a>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp all_ready?(state) do
    state.players
    |> Map.values()
    |> Enum.filter(& &1.connected)
    |> Enum.all?(& &1.ready)
  end

  defp can_start?(state) do
    connected_count =
      state.players
      |> Map.values()
      |> Enum.count(& &1.connected)

    connected_count >= 2
  end

  defp get_current_author(state) do
    if state.current_question_index do
      Enum.at(state.player_order, state.current_question_index)
    else
      nil
    end
  end

  defp get_current_question(state) do
    author_id = get_current_author(state)

    if author_id do
      state.players[author_id].question || %{text: "", answers: []}
    else
      %{text: "", answers: []}
    end
  end

  defp sort_by_score(players) do
    players
    |> Enum.sort_by(fn {_, player} -> player.total_score end, :desc)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(6)
    |> Base.url_encode64(padding: false)
    |> String.downcase()
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp ensure_session_exists(session_id) do
    case Registry.lookup(GenServerIo.TruthOrLie.Registry, session_id) do
      [{_pid, _}] ->
        :ok

      [] ->
        # Try to start the session
        case start_session(session_id, 15) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          _ -> {:error, :not_found}
        end
    end
  end

  defp start_session(session_id, target_score) do
    DynamicSupervisor.start_child(
      GenServerIo.TruthOrLie.Supervisor,
      {Server, session_id: session_id, target_score: target_score}
    )
  end

  defp format_time(nil), do: "0:00"

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "0:00"
end
