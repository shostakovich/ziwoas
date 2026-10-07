defmodule Ziwoas.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    config = boot_config()

    children =
      [
        Ziwoas.Repo,
        {Phoenix.PubSub, name: Ziwoas.PubSub},
        ZiwoasWeb.Endpoint
      ] ++ collector(config) ++ scheduler(config)

    Supervisor.start_link(children, strategy: :one_for_one, name: Ziwoas.Supervisor)
  end

  # Device connections; none in tests.
  defp collector(nil), do: []

  defp collector(config) do
    if Application.get_env(:ziwoas, :collector, true),
      do: [{Ziwoas.Collector, config: config}],
      else: []
  end

  @doc false
  # The config the collector and the scheduler start from. Without a readable config
  # Phoenix serves pages, but connects to no device and schedules nothing.
  def boot_config(load \\ &Ziwoas.Config.app_config/0) do
    load.()
  rescue
    error in Ziwoas.Config.Error ->
      Logger.error("config: #{Exception.message(error)}; no collector, no scheduler")
      nil
  end

  defp scheduler(nil), do: []

  defp scheduler(config) do
    jobs = Application.get_env(:ziwoas, Ziwoas.Scheduler, [])[:jobs] || []

    if Application.get_env(:ziwoas, :scheduler, true) and jobs != [],
      do: [{Ziwoas.Scheduler, jobs: jobs, zone: config.location.timezone}],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    ZiwoasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
