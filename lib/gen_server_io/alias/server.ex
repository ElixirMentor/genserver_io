defmodule GenServerIo.Alias.Server do
  use GenServer
  require Logger
  alias GenServerIo.Alias.WordSets

  # Cleanup configuration - remove players disconnected for more than 10 minutes
  # Run cleanup every 5 minutes
  @cleanup_interval_ms 5 * 60 * 1000
  # Remove after 10 minutes disconnected
  @disconnect_timeout_ms 10 * 60 * 1000
  # Remove entire session after 1 hour of inactivity
  @session_timeout_ms 60 * 60 * 1000

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via_tuple(session_id))
  end

  def create_session(session_id, difficulty, target_score \\ 30, language \\ :en) do
    case DynamicSupervisor.start_child(
           GenServerIo.Alias.Supervisor,
           {__MODULE__, session_id}
         ) do
      {:ok, _pid} ->
        GenServer.call(via_tuple(session_id), {:set_difficulty, difficulty})
        GenServer.call(via_tuple(session_id), {:set_target_score, target_score})
        GenServer.call(via_tuple(session_id), {:set_language, language})
        {:ok, session_id}

      {:error, {:already_started, _pid}} ->
        {:ok, session_id}
    end
  end

  def join_session(session_id, user_id, nickname) do
    GenServer.call(via_tuple(session_id), {:join, user_id, nickname})
  end

  def leave_session(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:leave, user_id})
  end

  def join_team(session_id, user_id, team_name) do
    GenServer.call(via_tuple(session_id), {:join_team, user_id, team_name})
  end

  def rejoin_team(session_id, user_id, team_name) do
    GenServer.call(via_tuple(session_id), {:rejoin_team, user_id, team_name})
  end

  def mark_connected(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:mark_connected, user_id})
  end

  def cleanup_disconnected_players(session_id) do
    GenServer.call(via_tuple(session_id), :cleanup_disconnected_players)
  end

  def check_nickname_availability(session_id, nickname) do
    GenServer.call(via_tuple(session_id), {:check_nickname_availability, nickname})
  end

  def reclaim_nickname(session_id, user_id, nickname) do
    GenServer.call(via_tuple(session_id), {:reclaim_nickname, user_id, nickname})
  end

  def leave_team(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:leave_team, user_id})
  end

  def set_ready(session_id, user_id, ready) do
    GenServer.call(via_tuple(session_id), {:set_ready, user_id, ready})
  end

  def start_game(session_id, starter_user_id) do
    GenServer.call(via_tuple(session_id), {:start_game, starter_user_id})
  end

  def next_word(session_id, user_id, action) do
    GenServer.call(via_tuple(session_id), {:next_word, user_id, action})
  end

  def score_word(session_id, word_index, score) do
    GenServer.call(via_tuple(session_id), {:score_word, word_index, score})
  end

  def next_round(session_id) do
    GenServer.call(via_tuple(session_id), :next_round)
  end

  def reset_to_lobby(session_id) do
    GenServer.call(via_tuple(session_id), :reset_to_lobby)
  end

  def get_state(session_id) do
    case GenServer.whereis(via_tuple(session_id)) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(via_tuple(session_id), :get_state)
    end
  end

  def get_next_explainer(session_id) do
    case GenServer.whereis(via_tuple(session_id)) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(via_tuple(session_id), :get_next_explainer)
    end
  end

  defp via_tuple(session_id) do
    {:via, Registry, {GenServerIo.Alias.Registry, session_id}}
  end

  @impl true
  def init(session_id) do
    # Schedule the first cleanup
    cleanup_timer =
      Process.send_after(self(), :cleanup_disconnected_players, @cleanup_interval_ms)

    current_time = DateTime.utc_now()

    {:ok,
     %{
       session_id: session_id,
       difficulty: :medium,
       language: :en,
       phase: :lobby,
       players: %{},
       teams: [],
       current_team: 0,
       current_explainer: nil,
       next_explainer: nil,
       current_word: nil,
       words_used: [],
       remaining_words: [],
       round_start_time: nil,
       timer_ref: nil,
       time_remaining: nil,
       target_score: 30,
       game_ever_started: false,
       cleanup_timer_ref: cleanup_timer,
       created_at: current_time,
       last_activity: current_time
     }}
  end

  @impl true
  def handle_call({:set_difficulty, difficulty}, _from, state) do
    words = WordSets.get_words(difficulty, state.language) |> Enum.shuffle()
    new_state = %{state | difficulty: difficulty, remaining_words: words}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_target_score, target_score}, _from, state) do
    new_state = %{state | target_score: target_score}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_language, language}, _from, state) do
    # Update remaining words when language changes
    words = WordSets.get_words(state.difficulty, language) |> Enum.shuffle()
    new_state = %{state | language: language, remaining_words: words}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:join, user_id, nickname}, _from, state) do
    # Check if nickname is already taken
    existing_nicknames =
      state.players
      |> Map.values()
      |> Enum.map(& &1.nickname)
      |> MapSet.new()

    if MapSet.member?(existing_nicknames, nickname) do
      {:reply, {:error, :nickname_taken}, state}
    else
      new_players =
        Map.put(state.players, user_id, %{
          nickname: nickname,
          team: nil,
          ready: false,
          connected: true,
          total_points: 0
        })

      new_state =
        %{state | players: new_players}
        |> update_last_activity()

      broadcast_update(new_state)
      {:reply, {:ok, new_state}, new_state}
    end
  end

  @impl true
  def handle_call({:leave, user_id}, _from, state) do
    # Instead of removing the player completely, mark them as disconnected
    # This preserves their session for restore functionality
    player = Map.get(state.players, user_id)

    if player do
      # Mark player as disconnected but keep their data with timestamp
      disconnect_time = DateTime.utc_now()

      updated_player =
        player
        |> Map.put(:connected, false)
        |> Map.put(:disconnected_at, disconnect_time)

      updated_players = Map.put(state.players, user_id, updated_player)

      # Remove from team members list but keep team assignment in player data
      new_teams =
        Enum.map(state.teams, fn team ->
          %{team | members: Enum.reject(team.members, &(&1 == user_id))}
        end)
        # Only remove empty teams if game hasn't started yet
        # This preserves team structure during active games when players refresh/disconnect
        |> then(fn teams ->
          if Map.get(state, :game_ever_started, false) do
            teams
          else
            Enum.reject(teams, &Enum.empty?(&1.members))
          end
        end)

      # Clear current_explainer if the leaving player was the explainer
      updated_current_explainer =
        if state.current_explainer == user_id do
          # Find a new explainer from the first team with members
          case Enum.find(new_teams, &(length(&1.members) > 0)) do
            nil -> nil
            team -> List.first(team.members)
          end
        else
          state.current_explainer
        end

      new_state = %{
        state
        | players: updated_players,
          teams: new_teams,
          current_explainer: updated_current_explainer
      }

      broadcast_update(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:check_nickname_availability, nickname}, _from, state) do
    # Check if nickname exists and if the player using it is connected
    case Enum.find(state.players, fn {_id, player} -> player.nickname == nickname end) do
      nil ->
        {:reply, :available, state}

      {_user_id, player} ->
        if Map.get(player, :connected, true) do
          {:reply, :taken_by_connected, state}
        else
          {:reply, :taken_by_disconnected, state}
        end
    end
  end

  @impl true
  def handle_call({:reclaim_nickname, user_id, nickname}, _from, state) do
    # Find the disconnected player with this nickname and remove them
    {updated_players, reclaimed} =
      Enum.reduce(state.players, {%{}, false}, fn {id, player}, {acc_players, found} ->
        if player.nickname == nickname and not Map.get(player, :connected, true) do
          # Skip this player (remove them) and mark as found
          {acc_players, true}
        else
          # Keep this player
          {Map.put(acc_players, id, player), found}
        end
      end)

    if reclaimed do
      # Add the new player with the reclaimed nickname
      new_players =
        Map.put(updated_players, user_id, %{
          nickname: nickname,
          team: nil,
          ready: false,
          connected: true,
          total_points: 0
        })

      new_state = %{state | players: new_players}
      broadcast_update(new_state)
      {:reply, {:ok, new_state}, new_state}
    else
      {:reply, {:error, :nickname_not_available}, state}
    end
  end

  @impl true
  def handle_call(:cleanup_disconnected_players, _from, state) do
    # Perform manual cleanup
    cleaned_state = perform_cleanup(state)

    # Broadcast if any players were removed
    if map_size(state.players) != map_size(cleaned_state.players) do
      broadcast_update(cleaned_state)
    end

    {:reply, :ok, cleaned_state}
  end

  @impl true
  def handle_call({:mark_connected, user_id}, _from, state) do
    player = Map.get(state.players, user_id)

    if player do
      # Mark player as connected
      updated_players = Map.put(state.players, user_id, %{player | connected: true})

      new_state =
        %{state | players: updated_players}
        |> update_last_activity()

      broadcast_update(new_state)
      {:reply, {:ok, new_state}, new_state}
    else
      {:reply, {:error, :player_not_found}, state}
    end
  end

  @impl true
  def handle_call({:rejoin_team, user_id, team_name}, _from, state) do
    # Rejoin team without restrictions (for session restoration)
    player = Map.get(state.players, user_id)

    if player do
      # Find the team
      team_exists = Enum.any?(state.teams, &(&1.name == team_name))

      if team_exists do
        # Add user back to their team
        updated_teams =
          Enum.map(state.teams, fn team ->
            if team.name == team_name do
              # Add user if not already in team
              if Enum.member?(team.members, user_id) do
                team
              else
                %{team | members: team.members ++ [user_id]}
              end
            else
              # Remove from other teams
              %{team | members: Enum.reject(team.members, &(&1 == user_id))}
            end
          end)

        # Update player's team and mark as connected
        updated_players =
          Map.put(state.players, user_id, %{player | team: team_name, connected: true})

        new_state = %{state | players: updated_players, teams: updated_teams}

        broadcast_update(new_state)
        {:reply, {:ok, new_state}, new_state}
      else
        {:reply, {:error, :team_not_found}, state}
      end
    else
      {:reply, {:error, :player_not_found}, state}
    end
  end

  @impl true
  def handle_call({:join_team, user_id, team_request}, _from, state) do
    # Prevent team changes only during active gameplay
    if state.phase == :playing do
      {:reply, {:error, :no_team_changes_during_play}, state}
    else
      player = Map.get(state.players, user_id)

      if player do
        # Remove from current team
        updated_teams =
          Enum.map(state.teams, fn team ->
            %{team | members: Enum.reject(team.members, &(&1 == user_id))}
          end)
          |> Enum.reject(&Enum.empty?(&1.members))

        # Determine team to join
        {final_teams, team_name} =
          if team_request == "new" do
            # Find the next team number that doesn't exist yet
            existing_team_numbers =
              updated_teams
              |> Enum.map(& &1.name)
              |> Enum.filter(&String.starts_with?(&1, "Team "))
              |> Enum.map(fn "Team " <> num_str -> String.to_integer(num_str) end)
              |> Enum.sort()

            # Find the next available team number
            team_number =
              case existing_team_numbers do
                [] -> 1
                numbers -> find_next_team_number(numbers, 1)
              end

            team_name = "Team #{team_number}"
            new_team = %{name: team_name, members: [user_id], score: 0}
            {updated_teams ++ [new_team], team_name}
          else
            # Join existing team by name
            case Enum.find(updated_teams, &(&1.name == team_request)) do
              nil ->
                # Team doesn't exist, create it (fallback safety)
                team_name = team_request
                new_team = %{name: team_name, members: [user_id], score: 0}
                {updated_teams ++ [new_team], team_name}

              _existing_team ->
                updated =
                  Enum.map(updated_teams, fn t ->
                    if t.name == team_request do
                      %{t | members: t.members ++ [user_id]}
                    else
                      t
                    end
                  end)

                {updated, team_request}
            end
          end

        updated_players =
          Map.put(state.players, user_id, %{player | team: team_name, ready: false})

        new_state = %{state | players: updated_players, teams: final_teams}
        broadcast_update(new_state)
        {:reply, {:ok, new_state}, new_state}
      else
        {:reply, {:error, :player_not_found}, state}
      end
    end
  end

  @impl true
  def handle_call({:leave_team, user_id}, _from, state) do
    # Prevent team changes only during active gameplay
    if state.phase == :playing do
      {:reply, {:error, :no_team_changes_during_play}, state}
    else
      player = Map.get(state.players, user_id)

      if player do
        # Remove from current team
        updated_teams =
          Enum.map(state.teams, fn team ->
            %{team | members: Enum.reject(team.members, &(&1 == user_id))}
          end)
          |> Enum.reject(&Enum.empty?(&1.members))

        # Set player team to nil (back to waiting room)
        updated_players = Map.put(state.players, user_id, %{player | team: nil, ready: false})
        new_state = %{state | players: updated_players, teams: updated_teams}
        broadcast_update(new_state)
        {:reply, {:ok, new_state}, new_state}
      else
        {:reply, {:error, :player_not_found}, state}
      end
    end
  end

  @impl true
  def handle_call({:set_ready, user_id, ready}, _from, state) do
    case Map.get(state.players, user_id) do
      nil ->
        {:reply, {:error, :player_not_found}, state}

      player ->
        updated_players = Map.put(state.players, user_id, %{player | ready: ready})
        new_state = %{state | players: updated_players}
        broadcast_update(new_state)
        {:reply, {:ok, new_state}, new_state}
    end
  end

  @impl true
  def handle_call({:start_game, starter_user_id}, _from, state) do
    if can_start_game?(state) do
      # Check if starter is a valid ready player
      starter_player = Map.get(state.players, starter_user_id)

      # Determine who should be the explainer
      designated_first_explainer =
        if state.current_explainer && Map.has_key?(state.players, state.current_explainer) do
          # Subsequent rounds: use pre-determined explainer if they still exist
          state.current_explainer
        else
          # First round or explainer left: use starter if they're ready, otherwise first member of first team
          if starter_player && starter_player.ready && starter_player.team do
            starter_user_id
          else
            first_team = List.first(state.teams)
            # Find first valid team member
            Enum.find(first_team.members, &Map.has_key?(state.players, &1)) || starter_user_id
          end
        end

      # Allow start if user is the designated explainer OR if there's no valid explainer and user is ready
      valid_to_start =
        starter_user_id == designated_first_explainer ||
          (!Map.has_key?(state.players, designated_first_explainer) && starter_player &&
             starter_player.ready)

      if valid_to_start do
        # Ensure we have words available
        words =
          if length(state.remaining_words) > 0 do
            state.remaining_words
          else
            # Fallback: get words for current difficulty and language
            WordSets.get_words(state.difficulty, state.language) |> Enum.shuffle()
          end

        first_word = List.first(words)
        # Use the starter as explainer if the designated one doesn't exist
        first_explainer =
          if Map.has_key?(state.players, designated_first_explainer) do
            designated_first_explainer
          else
            starter_user_id
          end

        # Cancel any existing timer
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

        # Start 60-second timer
        timer_ref = Process.send_after(self(), :time_up, 60_000)

        # Calculate next explainer for future rounds
        next_explainer =
          calculate_next_explainer(%{state | current_explainer: first_explainer, current_team: 0})

        new_state = %{
          state
          | phase: :playing,
            current_word: first_word,
            current_explainer: first_explainer,
            next_explainer: next_explainer,
            remaining_words: List.delete(words, first_word),
            round_start_time: DateTime.utc_now(),
            timer_ref: timer_ref,
            time_remaining: 60,
            game_ever_started: true
        }

        # Start countdown updates every second
        schedule_timer_update()

        broadcast_update(new_state)
        {:reply, {:ok, new_state}, new_state}
      else
        {:reply, {:error, :not_first_explainer}, state}
      end
    else
      {:reply, {:error, :cannot_start}, state}
    end
  end

  @impl true
  def handle_call({:next_word, user_id, _action}, _from, state) do
    # Allow next word if user is the explainer OR if explainer is missing and user is on the explaining team
    explainer_exists = Map.has_key?(state.players, state.current_explainer)
    current_team = if state.current_team, do: Enum.at(state.teams, state.current_team), else: nil
    user_on_explaining_team = current_team && Enum.member?(current_team.members, user_id)

    can_explain =
      state.current_explainer == user_id || (!explainer_exists && user_on_explaining_team)

    if can_explain and state.phase == :playing and (state.time_remaining || 0) > 0 do
      # If a new player is taking over, update the current_explainer
      updated_state =
        if !explainer_exists && user_on_explaining_team do
          %{state | current_explainer: user_id}
        else
          state
        end

      # Default all words to +1 score, store "next" as status but we'll treat it as explained
      word_result = %{word: updated_state.current_word, status: :next, score: 1}
      updated_words_used = [word_result | updated_state.words_used]

      case updated_state.remaining_words do
        [] ->
          # End round
          if updated_state.timer_ref, do: Process.cancel_timer(updated_state.timer_ref)

          new_state = %{
            updated_state
            | phase: :round_end,
              words_used: updated_words_used,
              current_word: nil,
              timer_ref: nil,
              time_remaining: nil
          }

          broadcast_update(new_state)
          {:reply, {:ok, new_state}, new_state}

        [next_word | rest] ->
          new_state = %{
            updated_state
            | current_word: next_word,
              remaining_words: rest,
              words_used: updated_words_used
          }

          broadcast_update(new_state)
          {:reply, {:ok, new_state}, new_state}
      end
    else
      {:reply, {:error, :not_allowed}, state}
    end
  end

  @impl true
  def handle_call({:score_word, word_index, score}, _from, state) do
    if state.phase == :round_end and word_index < length(state.words_used) do
      updated_words =
        state.words_used
        |> Enum.with_index()
        |> Enum.map(fn {word_data, idx} ->
          if idx == word_index do
            Map.put(word_data, :score, score)
          else
            word_data
          end
        end)

      new_state = %{state | words_used: updated_words}
      broadcast_update(new_state)
      {:reply, {:ok, new_state}, new_state}
    else
      {:reply, {:error, :invalid_scoring}, state}
    end
  end

  @impl true
  def handle_call(:reset_to_lobby, _from, state) do
    # Reset game state to lobby phase while preserving players but clearing team assignments
    reset_state = %{
      state
      | phase: :lobby,
        current_team: 0,
        current_explainer: nil,
        current_word: nil,
        remaining_words: WordSets.get_words(state.difficulty, state.language) |> Enum.shuffle(),
        words_used: [],
        timer_ref: nil,
        time_remaining: nil,
        game_ever_started: false,
        # Clear teams to allow rebuilding
        teams: []
    }

    # Reset all players' team and ready status
    reset_players =
      state.players
      |> Enum.map(fn {user_id, player} ->
        {user_id, %{player | team: nil, ready: false}}
      end)
      |> Map.new()

    final_state = %{reset_state | players: reset_players}
    broadcast_update(final_state)
    {:reply, {:ok, final_state}, final_state}
  end

  @impl true
  def handle_call(:next_round, _from, state) do
    if state.phase == :round_end do
      # Check if we have teams
      if length(state.teams) == 0 do
        {:reply, {:error, :no_teams}, state}
      else
        # Calculate scores
        round_score =
          state.words_used
          |> Enum.map(&Map.get(&1, :score, 0))
          |> Enum.sum()

        # Update current team's score
        current_team = Enum.at(state.teams, state.current_team)

        if current_team do
          new_score = current_team.score + round_score

          updated_teams =
            state.teams
            |> Enum.with_index()
            |> Enum.map(fn {team, idx} ->
              if idx == state.current_team do
                %{team | score: new_score}
              else
                team
              end
            end)

          # Update total_points only for the explainer who scored the points
          updated_players_with_points =
            state.players
            |> Enum.map(fn {user_id, player} ->
              # Only give points to the current explainer
              if user_id == state.current_explainer do
                current_total = Map.get(player, :total_points, 0)
                {user_id, %{player | total_points: current_total + round_score}}
              else
                {user_id, player}
              end
            end)
            |> Map.new()

          # Check for winner
          if new_score >= state.target_score do
            new_state = %{
              state
              | phase: :game_over,
                teams: updated_teams,
                current_word: nil,
                words_used: [],
                timer_ref: nil,
                time_remaining: nil,
                players: updated_players_with_points
            }

            broadcast_update(new_state)
            {:reply, {:ok, new_state}, new_state}
          else
            # Reset all players' ready status when returning to lobby
            reset_players =
              updated_players_with_points
              |> Enum.map(fn {user_id, player} ->
                {user_id, %{player | ready: false}}
              end)
              |> Map.new()

            # Find teams that still have active players
            teams_with_active_players =
              updated_teams
              |> Enum.map(fn team ->
                active_members = Enum.filter(team.members, &Map.has_key?(reset_players, &1))
                %{team | members: active_members}
              end)
              |> Enum.filter(&(length(&1.members) > 0))

            # Calculate next explainer based on active teams
            {next_team_index, valid_explainer} =
              if length(teams_with_active_players) > 0 do
                if length(teams_with_active_players) == 1 do
                  # Single team: rotate explainer within team
                  current_team = List.first(teams_with_active_players)

                  # Find current explainer index if they still exist
                  current_explainer_index =
                    if Map.has_key?(reset_players, state.current_explainer) do
                      Enum.find_index(current_team.members, &(&1 == state.current_explainer))
                    else
                      nil
                    end

                  # Calculate next explainer
                  next_explainer_index =
                    if current_explainer_index do
                      rem(current_explainer_index + 1, length(current_team.members))
                    else
                      # Start from first member if current explainer is gone
                      0
                    end

                  next_explainer = Enum.at(current_team.members, next_explainer_index)
                  {0, next_explainer}
                else
                  # Multiple teams: find next valid team
                  current_team_still_exists =
                    Enum.find_index(teams_with_active_players, fn team ->
                      team.name == Enum.at(state.teams, state.current_team, %{}).name
                    end)

                  next_team_index =
                    if current_team_still_exists do
                      rem(current_team_still_exists + 1, length(teams_with_active_players))
                    else
                      # Start from first team if current team is gone
                      0
                    end

                  next_team = Enum.at(teams_with_active_players, next_team_index)
                  next_explainer = List.first(next_team.members)
                  {next_team_index, next_explainer}
                end
              else
                # No active teams
                {0, nil}
              end

            # Return to lobby - don't start next round automatically
            new_state = %{
              state
              | phase: :lobby,
                # Use teams with only active players
                teams: teams_with_active_players,
                current_team: next_team_index,
                current_explainer: valid_explainer,
                next_explainer: nil,
                current_word: nil,
                words_used: [],
                timer_ref: nil,
                time_remaining: nil,
                players: reset_players
            }

            broadcast_update(new_state)
            {:reply, {:ok, new_state}, new_state}
          end
        else
          {:reply, {:error, :no_current_team}, state}
        end
      end
    else
      {:reply, {:error, :not_round_end}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:get_next_explainer, _from, state) do
    next_explainer = calculate_next_explainer(state)
    {:reply, {:ok, next_explainer}, state}
  end

  @impl true
  def handle_info(:cleanup_disconnected_players, state) do
    # Perform cleanup and schedule next cleanup
    cleaned_state = perform_cleanup(state)

    # Schedule next cleanup
    cleanup_timer =
      Process.send_after(self(), :cleanup_disconnected_players, @cleanup_interval_ms)

    new_state = %{cleaned_state | cleanup_timer_ref: cleanup_timer}

    # Broadcast if any players were removed
    if map_size(state.players) != map_size(cleaned_state.players) do
      broadcast_update(new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:time_up, state) do
    if state.phase == :playing do
      new_state = %{state | phase: :round_end, timer_ref: nil, time_remaining: 0}
      broadcast_update(new_state)
      Phoenix.PubSub.broadcast(GenServerIo.PubSub, "game:#{state.session_id}", :timer_finished)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:timer_update, state) do
    if (state.phase == :playing and state.time_remaining) && state.time_remaining > 0 do
      new_time = state.time_remaining - 1
      new_state = %{state | time_remaining: new_time}

      if new_time > 0 do
        schedule_timer_update()
      end

      broadcast_update(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  defp can_start_game?(state) do
    teams_with_members = Enum.filter(state.teams, &(length(&1.members) > 0))
    total_team_members = teams_with_members |> Enum.map(&length(&1.members)) |> Enum.sum()

    # Need at least 1 team with 2+ total players across all teams
    length(teams_with_members) >= 1 and total_team_members >= 2 and all_players_ready?(state)
  end

  defp all_players_ready?(state) do
    team_members = state.teams |> Enum.flat_map(& &1.members) |> MapSet.new()

    # If no team members exist, game cannot start
    if MapSet.size(team_members) == 0 do
      false
    else
      # Only check ready status of team members (ignore waiting room players)
      team_members
      |> Enum.all?(fn user_id ->
        case Map.get(state.players, user_id) do
          %{ready: true} -> true
          _ -> false
        end
      end)
    end
  end

  defp find_next_team_number([], current), do: current

  defp find_next_team_number([head | tail], current) do
    if head == current do
      find_next_team_number(tail, current + 1)
    else
      current
    end
  end

  defp schedule_timer_update do
    Process.send_after(self(), :timer_update, 1000)
  end

  defp calculate_next_explainer(state) do
    if length(state.teams) == 0 do
      nil
    else
      if length(state.teams) == 1 do
        # Single team: rotate explainer within team
        current_team = List.first(state.teams)

        if current_team && length(current_team.members) > 0 do
          current_explainer_index =
            Enum.find_index(current_team.members, &(&1 == state.current_explainer))

          next_explainer_index =
            rem((current_explainer_index || 0) + 1, length(current_team.members))

          Enum.at(current_team.members, next_explainer_index)
        else
          nil
        end
      else
        # Multiple teams: switch to next team
        next_team_index = rem((state.current_team || 0) + 1, length(state.teams))
        next_team = Enum.at(state.teams, next_team_index)

        if next_team && length(next_team.members) > 0 do
          List.first(next_team.members)
        else
          nil
        end
      end
    end
  end

  defp perform_cleanup(state) do
    current_time = DateTime.utc_now()

    # Check if the session should be terminated due to inactivity
    last_activity = Map.get(state, :last_activity, state.created_at || current_time)
    session_age_ms = DateTime.diff(current_time, last_activity, :millisecond)

    if session_age_ms > @session_timeout_ms do
      Logger.info("Terminating inactive session #{state.session_id} after #{session_age_ms}ms")
      # Terminate the session after 1 hour of inactivity
      Process.exit(self(), :session_timeout)
      state
    else
      # Filter out players who have been disconnected for too long
      cleaned_players =
        Enum.reduce(state.players, %{}, fn {user_id, player}, acc ->
          should_remove =
            case Map.get(player, :connected, true) do
              # Keep connected players
              true ->
                false

              false ->
                # Check if disconnected for too long
                case Map.get(player, :disconnected_at) do
                  # No disconnect timestamp, keep for safety
                  nil ->
                    false

                  disconnect_time ->
                    time_diff_ms = DateTime.diff(current_time, disconnect_time, :millisecond)
                    time_diff_ms >= @disconnect_timeout_ms
                end
            end

          if should_remove do
            # Don't add to the accumulator (remove player)
            acc
          else
            # Keep player
            Map.put(acc, user_id, player)
          end
        end)

      # If players were removed, also clean up teams
      if map_size(cleaned_players) != map_size(state.players) do
        # Update team members to remove cleaned players
        cleaned_teams =
          Enum.map(state.teams, fn team ->
            active_members = Enum.filter(team.members, &Map.has_key?(cleaned_players, &1))
            %{team | members: active_members}
          end)
          # Remove empty teams if game hasn't started yet
          |> then(fn teams ->
            if Map.get(state, :game_ever_started, false) do
              teams
            else
              Enum.filter(teams, &(length(&1.members) > 0))
            end
          end)

        # Update current explainer if they were removed
        updated_current_explainer =
          if Map.has_key?(cleaned_players, state.current_explainer || "") do
            state.current_explainer
          else
            # Find a new explainer from available team members
            case Enum.find(cleaned_teams, &(length(&1.members) > 0)) do
              nil -> nil
              team -> List.first(team.members)
            end
          end

        %{
          state
          | players: cleaned_players,
            teams: cleaned_teams,
            current_explainer: updated_current_explainer
        }
      else
        # No changes needed
        state
      end
    end
  end

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(
      GenServerIo.PubSub,
      "game:#{state.session_id}",
      {:game_update, state}
    )
  end

  defp update_last_activity(state) do
    Map.put(state, :last_activity, DateTime.utc_now())
  end
end
