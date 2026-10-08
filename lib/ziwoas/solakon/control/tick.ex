defmodule Ziwoas.Solakon.Control.Tick do
  @moduledoc false
  alias Ziwoas.Solakon.{Client, Control, Monitor, Reading}
  alias Ziwoas.Solakon.Control.{LoadReader, Outcome, Policy, State}

  @doc "Options: `:monitor` (server), `:offline_after_s`."
  @spec run(Reading.t(), Ziwoas.Plugs.Roster.t(), DateTime.t(), keyword) :: Outcome.t()
  def run(%Reading{} = reading, roster, now, opts \\ []) do
    control = Control.state!()

    if State.active?(control) do
      load = LoadReader.load_estimate(roster, now, Keyword.take(opts, [:offline_after_s]))
      decision = Policy.decide(reading, load, previous(control, now))
      monitor = Keyword.get(opts, :monitor, Monitor)

      case apply_control(monitor, decision.target_w) do
        :ok ->
          control |> Control.store!(decision, now) |> Control.reset_failures!()
          %Outcome{status: :applied, decision: decision, load: load, reading: reading}

        {:error, reason} ->
          after_write_failure(control, monitor, reason)
      end
    else
      %Outcome{status: :paused}
    end
  end

  @doc "The stored decision unless the inverter's watchdog has dropped it since."
  def previous(control, now) do
    with {decision, at} <- State.stored(control),
         :gt <- DateTime.compare(at, DateTime.add(now, -Client.remote_timeout_s())) do
      decision
    else
      _ -> nil
    end
  end

  # A down or stuck monitor counts as a failed write, so control is still handed back.
  defp apply_control(monitor, target_w) do
    Monitor.apply_control(monitor, target_w, Reading.min_soc_pct())
  catch
    :exit, reason -> {:error, {:monitor_down, reason}}
  end

  defp after_write_failure(control, monitor, reason) do
    control = Control.count_failure!(control)
    failures = control.consecutive_failures
    error = inspect(reason)

    if failures < Outcome.max_consecutive_failures(),
      do: %Outcome{status: :failed, failures: failures, error: error},
      else: release(control, monitor, failures, error)
  end

  defp release(control, monitor, failures, error) do
    case release_control(monitor) do
      :ok ->
        control |> Control.clear!() |> Control.reset_failures!()
        %Outcome{status: :released, failures: failures, error: error}

      {:error, reason} ->
        %Outcome{
          status: :failed,
          failures: failures,
          error: "#{error}; could not relinquish remote control: #{inspect(reason)}"
        }
    end
  end

  defp release_control(monitor) do
    Monitor.release_control(monitor)
  catch
    :exit, reason -> {:error, {:monitor_down, reason}}
  end
end
