defmodule GenServerIo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GenServerIoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:gen_server_io, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GenServerIo.PubSub},
      # Alias game infrastructure
      {Registry, keys: :unique, name: GenServerIo.Alias.Registry},
      {DynamicSupervisor, name: GenServerIo.Alias.Supervisor, strategy: :one_for_one},
      # Anagrams game infrastructure
      {Registry, keys: :unique, name: GenServerIo.Anagrams.Registry},
      {DynamicSupervisor, name: GenServerIo.Anagrams.Supervisor, strategy: :one_for_one},
      # Truth or Lie game infrastructure
      {Registry, keys: :unique, name: GenServerIo.TruthOrLie.Registry},
      {DynamicSupervisor, name: GenServerIo.TruthOrLie.Supervisor, strategy: :one_for_one},
      # Wordle Battle game infrastructure
      {Registry, keys: :unique, name: GenServerIo.WordleBattle.Registry},
      {DynamicSupervisor, name: GenServerIo.WordleBattle.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      GenServerIoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GenServerIo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GenServerIoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
