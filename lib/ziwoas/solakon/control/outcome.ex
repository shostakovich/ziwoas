defmodule Ziwoas.Solakon.Control.Outcome do
  @moduledoc """
  One answer per control tick (Rails' `Solakon::Control::Outcome`): applied, paused,
  failed or released, and the line the monitor logs for it — Rails' wording, so both
  apps' logs read alike. A dry run's tick is `applied` with `dry_run: true` and the
  writes it would have sent.
  """
  alias Ziwoas.RubyNumeric
  alias Ziwoas.Solakon.Control.{Decision, Load}
  alias Ziwoas.Solakon.Reading

  @max_consecutive_failures 3

  defstruct status: nil,
            decision: nil,
            load: nil,
            reading: nil,
            failures: 0,
            error: nil,
            dry_run: false,
            writes: []

  @type status :: :applied | :paused | :failed | :released
  @type t :: %__MODULE__{
          status: status,
          decision: Decision.t() | nil,
          load: Load.t() | nil,
          reading: Reading.t() | nil,
          failures: non_neg_integer,
          error: String.t() | nil,
          dry_run: boolean,
          writes: [term]
        }

  def max_consecutive_failures, do: @max_consecutive_failures

  @spec log_level(t) :: :info | :warning
  def log_level(%__MODULE__{status: status}) when status in [:applied, :paused], do: :info
  def log_level(%__MODULE__{}), do: :warning

  @spec log_line(t) :: String.t()
  def log_line(%__MODULE__{status: :applied} = outcome) do
    %{decision: decision, load: load, reading: reading} = outcome

    "state=#{decision.state} target=#{decision.target_w}W load=#{measured_load(load)} " <>
      "floor=#{round(load.floor_w)}W " <>
      "soc=#{reading.battery_soc_pct}% temp=#{ruby_s(reading.battery_temperature_c)}C " <>
      "pv=#{ruby_s(reading.pv_power_w)}W battery=#{ruby_s(reading.battery_power_w)}W"
  end

  def log_line(%__MODULE__{status: :paused}), do: "runtime paused"
  def log_line(%__MODULE__{status: :failed} = outcome), do: failure_line(outcome)

  def log_line(%__MODULE__{status: :released} = outcome),
    do: failure_line(outcome) <> " — relinquished remote control"

  defp measured_load(%Load{current_w: nil}), do: "stale"
  defp measured_load(%Load{current_w: watts}), do: "#{round(watts)}W"

  defp failure_line(outcome),
    do: "Modbus failure #{outcome.failures}/#{@max_consecutive_failures}: #{outcome.error}"

  defp ruby_s(nil), do: ""
  defp ruby_s(value), do: RubyNumeric.to_s(value)
end
