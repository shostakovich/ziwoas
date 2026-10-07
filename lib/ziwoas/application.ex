defmodule Ziwoas.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    {config, owners} = boot_config()
    # What started here is what runs: Ownership.owners/0 answers from these.
    Ziwoas.Ownership.put_boot_owners(owners)

    children =
      [Ziwoas.Repo] ++
        Ziwoas.Repo.writer_children(owners, Application.get_env(:ziwoas, :shadow_database)) ++
        lease(owners) ++
        [
          {Phoenix.PubSub, name: Ziwoas.PubSub},
          ZiwoasWeb.Endpoint
        ] ++ live_watchers(owners) ++ collector(config, owners) ++ scheduler(config)

    Supervisor.start_link(children, strategy: :one_for_one, name: Ziwoas.Supervisor)
  end

  # Polling bridges from Rails' writes to PubSub (issue #158), under their own
  # supervisor: a burst of watcher crashes exhausts its restarts, not the Endpoint's.
  defp live_watchers(owners) do
    if Application.get_env(:ziwoas, :live_watchers, true) do
      watchers = watchers(owners)

      [
        %{
          id: Ziwoas.Live.Supervisor,
          type: :supervisor,
          start:
            {Supervisor, :start_link,
             [watchers, [strategy: :one_for_one, name: Ziwoas.Live.Supervisor]]}
        }
      ]
    else
      []
    end
  end

  @doc """
  The watchers for `owners`: a watcher stands down for what Phoenix itself writes,
  because the owning task broadcasts after its own writes (`Ziwoas.Live.broadcast/3`).
  As owner of `sensor_poll` the poll job sends the sensors and weather beats; of
  `solakon_monitor` the monitor job sends the Solakon beat; of `plug_ingest` the
  Shelly handler sends the live deltas, and the dashboard watcher keeps only its
  minute summary beat (Rails' `DashboardSummaryJob`).
  """
  def watchers(owners) do
    if(owners.sensor_poll == :phoenix, do: [], else: [Ziwoas.Live.SensorsWatcher]) ++
      [{Ziwoas.Live.DashboardWatcher, live: owners.plug_ingest != :phoenix}] ++
      if(owners.solakon_monitor == :phoenix, do: [], else: [Ziwoas.Live.SolakonWatcher])
  end

  # The owner leases, taken before anything that acts starts (Ziwoas.Lease).
  defp lease(owners) do
    case Ziwoas.Lease.tasks(owners) do
      tasks when tasks != [] ->
        if Ziwoas.Lease.enabled?(), do: [{Ziwoas.Lease, tasks: tasks}], else: []

      [] ->
        []
    end
  end

  # Device connections of the tasks Phoenix runs (Phase 4); none in tests.
  defp collector(nil, _owners), do: []

  defp collector(config, owners) do
    if Application.get_env(:ziwoas, :collector, true),
      do: [{Ziwoas.Collector, config: config, owners: owners}],
      else: []
  end

  @doc false
  # The config and the owners that decide which writers and jobs start. Without a
  # readable config Phoenix owns nothing: it serves pages, writes and schedules nothing.
  def boot_config(load \\ &Ziwoas.Config.app_config/0) do
    config = load.()
    {config, config.owners}
  rescue
    error in Ziwoas.Config.Error ->
      Logger.error("config: #{Exception.message(error)}; Phoenix owns no task")
      {nil, Ziwoas.Ownership.all_rails()}
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
