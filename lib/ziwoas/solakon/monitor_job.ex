defmodule Ziwoas.Solakon.MonitorJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Config, Solakon}
  alias Ziwoas.Solakon.Control.{Outcome, Tick}
  alias Ziwoas.Solakon.Monitor

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)
    monitor = Keyword.get(opts, :monitor, Monitor)

    with {:ok, state} <- read(monitor),
         now = Clock.now(),
         {:ok, reading} <- store(state, now) do
      outcome = if config.solakon.control_enabled, do: control(reading, config, monitor, now)
      Solakon.notify_reading(reading)
      {:ok, reading, outcome}
    end
  end

  defp read(monitor) do
    with {:error, reason} = error <- Monitor.read_state(monitor) do
      Logger.warning("solakon_monitor: Modbus failure: #{inspect(reason)}")
      error
    end
  end

  defp store(state, now) do
    with {:error, changeset} = error <- Solakon.insert_reading(state, now) do
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
