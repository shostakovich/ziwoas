defmodule Ziwoas.Scheduler do
  @moduledoc """
  Phoenix's `config/recurring.yml`: one `Ziwoas.Scheduler.Runner` per job, under
  this supervisor. A job names its ownership task and runs only while that task is
  not `:rails` (`Ziwoas.Ownership`). Jobs come from

      config :ziwoas, Ziwoas.Scheduler,
        jobs: [
          fetch_current_weather: [task: :weather, schedule: "every 15 minutes",
                                  job: Ziwoas.Weather.CurrentJob]
        ]

  (keys as in `recurring.yml`), schedules in the configured zone
  (`location.timezone`). `Ziwoas.Application` starts it unless
  `config :ziwoas, scheduler: false` (test) or no job is configured.
  """
  use Supervisor

  alias Ziwoas.Scheduler.Runner

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    zone = Keyword.fetch!(opts, :zone)
    extra = Keyword.take(opts, [:clock, :timer])

    children =
      for {id, job} <- Keyword.fetch!(opts, :jobs) do
        {Runner,
         [id: id, zone: zone] ++
           Keyword.take(job, [:task, :schedule, :job, :shadow_offset]) ++ extra}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
