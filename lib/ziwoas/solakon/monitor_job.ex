defmodule Ziwoas.Solakon.MonitorJob do
  @moduledoc """
  Every 30 seconds: reads the inverter through `Ziwoas.Solakon.Monitor`, stores a
  `solakon_readings` row, runs the control tick on that reading
  (`Ziwoas.Solakon.Control.Tick`) while the configuration enables control, and
  sends `{:solakon_reading, id}` on `solakon`, the beat the dashboard and the PV
  page follow.
  """
  @behaviour Ziwoas.Scheduler.Job

  # Beyond the scheduler's context, tests pass `:config` and `:monitor`. A stored
  # reading returns `{:ok, reading, control_outcome_or_nil}`.

  require Logger

  alias Ziwoas.{Clock, Config, Repo}
  alias Ziwoas.Scheduler.Job
  alias Ziwoas.Solakon.{Monitor, Reading}
  alias Ziwoas.Solakon.Control.{Outcome, Tick}

  @impl true
  def perform(context) do
    config = Job.config(context)
    solakon = config.solakon

    cond do
      is_nil(solakon) -> Logger.info("solakon_monitor: not configured")
      not solakon.monitoring_enabled -> Logger.info("solakon_monitor: disabled")
      true -> run(config, Map.get(context, :monitor, Monitor))
    end
  end

  defp run(config, monitor) do
    with {:ok, state} <- read(monitor),
         now = Clock.now(),
         {:ok, reading} <- store(Reading.from_state(state, now)) do
      outcome = if config.solakon.control_enabled, do: control(reading, config, monitor, now)
      Phoenix.PubSub.broadcast(Ziwoas.PubSub, "solakon", {:solakon_reading, reading.id})
      {:ok, reading, outcome}
    end
  end

  defp read(monitor) do
    with {:error, reason} = error <- Monitor.read_state(monitor) do
      Logger.warning("solakon_monitor: Modbus failure: #{inspect(reason)}")
      error
    end
  end

  defp store(changeset) do
    with {:error, changeset} = error <- Repo.insert(changeset) do
      Logger.warning("solakon_monitor: invalid reading: #{inspect(changeset.errors)}")
      error
    end
  end

  defp control(reading, config, monitor, now) do
    outcome = Tick.run(reading, Config.plug_roster(config), now, monitor: monitor)
    Logger.log(Outcome.log_level(outcome), "solakon_control: #{Outcome.log_line(outcome)}")
    outcome
  end
end
