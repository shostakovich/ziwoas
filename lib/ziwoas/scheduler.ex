defmodule Ziwoas.Scheduler do
  @moduledoc """
  The recurring jobs: one `Ziwoas.Scheduler.Runner` per job the device config
  enables, under this supervisor. `jobs/1` is the table, schedules are
  `Ziwoas.Scheduler.Schedule`s on the local clock of `location.timezone`.

  `Ziwoas.Application` starts it with `config:` unless the config failed to
  load or `config :ziwoas, scheduler: false` (test).
  """
  use Supervisor

  alias Ziwoas.{Config, Location}
  alias Ziwoas.Scheduler.{Runner, Schedule}

  @type job :: {name :: atom, Schedule.t(), {module, keyword}}

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    opts
    |> Keyword.fetch!(:config)
    |> children(Keyword.take(opts, [:clock, :timer]))
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc """
  One runner per job of `jobs/1`. `runner_opts` go to every runner (tests:
  `:clock`, `:timer`).
  """
  @spec children(Config.t(), keyword) :: [Supervisor.child_spec() | {module, keyword}]
  def children(%Config{} = config, runner_opts \\ []) do
    for {name, schedule, job} <- jobs(config) do
      {Runner,
       [id: name, schedule: schedule, job: job, zone: config.location.timezone] ++ runner_opts}
    end
  end

  @doc "The jobs `config` enables; each job's opts carry the config."
  @spec jobs(Config.t()) :: [job]
  def jobs(%Config{} = config) do
    located? = Location.located?(config.location)
    inverter? = match?(%{monitoring_enabled: true}, config.solakon)
    sensors? = not is_nil(config.switchbot) and config.sensors != []
    switchable? = Enum.any?(config.plugs, & &1.switchable)
    energy_widget? = config.trmnl.energy_webhook_url not in [nil, ""]
    backup_dir = Application.get_env(:ziwoas, :backup_dir)

    for {name, schedule, module, opts, enabled?} <- [
          {:aggregate_energy_samples, {:daily, ~T[03:15:00]}, Ziwoas.Plugs.AggregatorJob,
           [backup_dir: backup_dir], true},
          {:fetch_current_weather, {:every, 15, :minute}, Ziwoas.Weather.CurrentJob, [],
           located?},
          {:fetch_today_weather, {:every, 1, :hour}, Ziwoas.Weather.TodayJob, [], located?},
          {:fetch_weather_forecast, {:every, 3, :hour}, Ziwoas.Weather.ForecastJob, [], located?},
          {:fetch_historic_weather, {:daily, ~T[03:45:00]}, Ziwoas.Weather.HistoricJob, [],
           located?},
          {:poll_sensors, {:every, 15, :minute}, Ziwoas.Sensors.PollJob, [], sensors?},
          {:push_trmnl_widget, {:every, 15, :minute}, Ziwoas.Trmnl.EnergyPushJob, [],
           energy_widget?},
          {:schedule_tick, {:every, 1, :minute}, Ziwoas.Switching.ScheduleTickJob, [],
           switchable?},
          {:solakon_monitor, {:every, 30, :second}, Ziwoas.Solakon.MonitorJob, [], inverter?},
          {:solakon_snapshot, {:every, 2, :minute}, Ziwoas.Solakon.SnapshotJob, [], inverter?}
        ],
        enabled? do
      {name, schedule, {module, [config: config] ++ opts}}
    end
  end
end
