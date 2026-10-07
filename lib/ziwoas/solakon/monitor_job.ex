defmodule Ziwoas.Solakon.MonitorJob do
  @moduledoc """
  Rails' `Solakon::MonitorJob` (`every 30 seconds`, task `solakon_monitor`): reads
  the inverter through `Ziwoas.Solakon.Monitor`, stores a `solakon_readings` row,
  runs the control tick on that reading (`Ziwoas.Solakon.Control.Tick`) while the
  configuration enables control and `solakon_control` runs in Phoenix, and as owner
  then sends `{:solakon_reading, id}` on `solakon`, the beat the dashboard and the PV
  page follow (Rails' `DashboardBroadcaster.broadcast_live`).

  `solakon_control` in `dry_run` decides on every reading of a shadowing monitor and
  sends nothing; as `phoenix` (together with `solakon_monitor`, as the ownership
  validation demands) it writes the inverter.
  """
  @behaviour Ziwoas.Scheduler.Job

  # Beyond the scheduler's context, tests pass `:config` and `:monitor`. A stored
  # reading returns `{:ok, reading, control_outcome_or_nil}`.

  require Logger

  alias Ziwoas.{Clock, Config, Live, Ownership, Repo}
  alias Ziwoas.Solakon.{Monitor, Reading}
  alias Ziwoas.Solakon.Control.{Outcome, Tick}

  @impl true
  def perform(%{task: task} = context) do
    config = Map.get_lazy(context, :config, &Config.app_config/0)
    solakon = config.solakon

    cond do
      is_nil(solakon) -> Logger.info("solakon_monitor: not configured")
      not solakon.monitoring_enabled -> Logger.info("solakon_monitor: disabled")
      true -> run(task, config, Map.get(context, :monitor, Monitor))
    end
  end

  defp run(task, config, monitor) do
    case Monitor.read_state(monitor) do
      {:ok, state} ->
        now = Clock.now()
        changeset = Reading.from_state(state, now)

        if changeset.valid? do
          reading = Repo.write(task, fn -> Repo.insert!(changeset) end)

          outcome =
            if config.solakon.control_enabled and Ownership.runs?(:solakon_control),
              do: control(reading, config, monitor, now)

          Live.broadcast(task, "solakon", {:solakon_reading, reading.id})

          {:ok, reading, outcome}
        else
          Logger.warning("solakon_monitor: invalid reading: #{inspect(changeset.errors)}")
        end

      {:error, reason} ->
        Logger.warning("solakon_monitor: Modbus failure: #{inspect(reason)}")
    end
  end

  defp control(reading, config, monitor, now) do
    outcome = Tick.run(reading, Config.plug_roster(config), now, monitor: monitor)
    Logger.log(Outcome.log_level(outcome), log_line(outcome))
    outcome
  end

  @doc "The decision log line: Rails' wording; a dry run names itself and the writes it held back."
  @spec log_line(Outcome.t()) :: String.t()
  def log_line(%Outcome{dry_run: true} = outcome),
    do:
      "solakon_control (dry_run): #{Outcome.log_line(outcome)} — not sent: " <>
        Enum.map_join(outcome.writes, ", ", &describe_write/1)

  def log_line(outcome), do: "solakon_control: #{Outcome.log_line(outcome)}"

  defp describe_write({:single, address, value}), do: "#{address}=#{value}"
  defp describe_write({:multiple, address, words}), do: "#{address}=#{inspect(words)}"
end
