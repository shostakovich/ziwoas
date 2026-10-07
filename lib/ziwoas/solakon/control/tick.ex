defmodule Ziwoas.Solakon.Control.Tick do
  @moduledoc """
  One pass of the control loop: read the household, decide a target, write it to
  the inverter through `Ziwoas.Solakon.Monitor`. `Ziwoas.Solakon.MonitorJob` runs
  it after each reading.

  What the loop remembers is the decision that reached the inverter: only a written
  target is stored, and a stored decision older than the inverter's 150 s watchdog is
  not continued. The target is written every tick, which re-arms that watchdog. Three
  write failures in a row hand control back (`release_control`) and forget it.
  """
  alias Ziwoas.Solakon.{Client, Monitor, Reading}
  alias Ziwoas.Solakon.Control.{LoadReader, Outcome, Policy, State}

  @doc "Options: `:monitor` (server), `:offline_after_s`."
  @spec run(Reading.t(), Ziwoas.Plugs.Roster.t(), DateTime.t(), keyword) :: Outcome.t()
  def run(%Reading{} = reading, roster, now, opts \\ []) do
    control = State.current!()

    if State.active?(control) do
      load = LoadReader.load_estimate(roster, now, Keyword.take(opts, [:offline_after_s]))
      decision = Policy.decide(reading, load, previous(control, now))
      monitor = Keyword.get(opts, :monitor, Monitor)

      case apply_control(monitor, decision.target_w) do
        :ok ->
          control |> State.store!(decision, now) |> State.reset_failures!()
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

  # A monitor that is down or stuck counts as a failed write, so control is still
  # handed back after the third one.
  defp apply_control(monitor, target_w) do
    Monitor.apply_control(monitor, target_w, Reading.min_soc_pct())
  catch
    :exit, reason -> {:error, {:monitor_down, reason}}
  end

  # Write failures only: a failed read never reaches the tick.
  defp after_write_failure(control, monitor, reason) do
    control = State.count_failure!(control)
    failures = control.consecutive_failures
    error = inspect(reason)

    if failures < Outcome.max_consecutive_failures(),
      do: %Outcome{status: :failed, failures: failures, error: error},
      else: release(control, monitor, failures, error)
  end

  defp release(control, monitor, failures, error) do
    case release_control(monitor) do
      :ok ->
        control |> State.clear!() |> State.reset_failures!()
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
