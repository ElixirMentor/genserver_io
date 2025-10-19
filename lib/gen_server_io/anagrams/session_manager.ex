defmodule GenServerIo.Anagrams.SessionManager do
  @moduledoc """
  Manages game session lifecycle and provides helper functions.
  """

  alias GenServerIo.Anagrams.Server

  @doc """
  Generates a unique session ID.
  """
  def generate_session_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
    |> String.downcase()
  end

  @doc """
  Checks if a session exists.
  """
  def session_exists?(session_id) do
    case Registry.lookup(GenServerIo.Anagrams.Registry, session_id) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Creates a new session with the given configuration.
  """
  def create_session(config \\ []) do
    session_id = generate_session_id()

    case Server.create_session(session_id, config) do
      {:ok, _pid} -> {:ok, session_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets session state if it exists.
  """
  def get_session(session_id) do
    if session_exists?(session_id) do
      Server.get_state(session_id)
    else
      {:error, :not_found}
    end
  end
end
