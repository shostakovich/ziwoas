defmodule Ziwoas.Application do
  @moduledoc false

  use Application

  require Logger

  alias Ziwoas.Config

  @collector Application.compile_env(:ziwoas, :collector, true)
  @scheduler Application.compile_env(:ziwoas, :scheduler, true)

  @impl true
  def start(_type, _args) do
    loaded = Config.load(Config.path())
    Config.put(loaded)

    with {:error, message} <- loaded,
         do: Logger.error("config: #{message}; no collector, no scheduler")

    Supervisor.start_link(children(loaded, collector: @collector, scheduler: @scheduler),
      strategy: :one_for_one,
      name: Ziwoas.Supervisor
    )
  end

  @doc false
  def children(loaded, opts) do
    [
      Ziwoas.Repo,
      {Phoenix.PubSub, name: Ziwoas.PubSub},
      {Registry, keys: :duplicate, name: Ziwoas.Shelly.registry()}
    ] ++
      devices(loaded, opts) ++ [ZiwoasWeb.Endpoint]
  end

  defp devices({:ok, config}, opts) do
    if(opts[:collector], do: [{Ziwoas.Collector, config: config}], else: []) ++
      if opts[:scheduler], do: [{Ziwoas.Scheduler, config: config}], else: []
  end

  defp devices({:error, _message}, _opts), do: []

  @impl true
  def config_change(changed, _new, removed) do
    ZiwoasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
