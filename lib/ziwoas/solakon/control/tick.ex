defmodule Ziwoas.Solakon.Control.Tick do
  @moduledoc """
  One pass of the control loop (Rails' `Solakon::Control::Tick`, task
  `solakon_control`): read the household, decide a target, write it to the inverter.
  `Ziwoas.Solakon.MonitorJob` runs it after each reading, as Rails' monitor does.

  What the loop remembers is the decision that reached the inverter: only a written
  target is stored, and a stored decision older than the inverter's 150 s watchdog is
  not continued. The target is written every tick, which re-arms that watchdog. Three
  write failures in a row hand control back (`release_control`) and forget it.

  Inputs come from the main database in every mode — the plugs' samples and the
  pause switch, which belongs to whoever owns the `PATCH /solakon/control` route.
  The decision state lives where the task writes (`Ziwoas.Repo.write/2`):

    * `:phoenix` — writes the registers through `Ziwoas.Solakon.Monitor`, then the
      main database's row;
    * `:dry_run` — writes nothing to the inverter; stores the decision in the shadow
      database's row as if the write had succeeded (that row mirrors Rails' pause
      switch), and the outcome carries the writes it would have sent. The register
      writes themselves are refused below this module as well
      (`Ziwoas.Solakon.Modbus`).
  """
  alias Ziwoas.{Ownership, Repo}
  alias Ziwoas.Solakon.{Client, Monitor, Reading}
  alias Ziwoas.Solakon.Control.{LoadReader, Outcome, Policy, State}

  @task :solakon_control

  @doc "Options: `:monitor` (server), `:offline_after_s`."
  @spec run(Reading.t(), Ziwoas.Plugs.Roster.t(), DateTime.t(), keyword) :: Outcome.t()
  def run(%Reading{} = reading, roster, now, opts \\ []) do
    owner? = Ownership.owner?(@task)

    if State.active?(State.current()) do
      load = LoadReader.load_estimate(roster, now, Keyword.take(opts, [:offline_after_s]))

      Repo.write(@task, fn ->
        control = State.current!() |> State.mirror_paused!(false)
        decision = Policy.decide(reading, load, previous(control, now))
        applied = %Outcome{status: :applied, decision: decision, load: load, reading: reading}

        if owner? do
          monitor = Keyword.get(opts, :monitor, Monitor)

          case Monitor.apply_control(monitor, decision.target_w, Reading.min_soc_pct()) do
            :ok -> stored(control, applied, now)
            {:error, reason} -> after_write_failure(control, monitor, reason)
          end
        else
          stored(control, %{applied | dry_run: true, writes: would_write(decision)}, now)
        end
      end)
    else
      Repo.write(@task, fn -> State.current!() |> State.mirror_paused!(true) end)
      %Outcome{status: :paused}
    end
  end

  defp stored(control, outcome, now) do
    control |> State.store!(outcome.decision, now) |> State.reset_failures!()
    outcome
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

  # Write failures only: a failed read never reaches the tick.
  defp after_write_failure(control, monitor, reason) do
    control = State.count_failure!(control)
    failures = control.consecutive_failures
    error = describe(reason)

    if failures < Outcome.max_consecutive_failures(),
      do: %Outcome{status: :failed, failures: failures, error: error},
      else: release(control, monitor, failures, error)
  end

  defp release(control, monitor, failures, error) do
    case Monitor.release_control(monitor) do
      :ok ->
        control |> State.clear!() |> State.reset_failures!()
        %Outcome{status: :released, failures: failures, error: error}

      {:error, reason} ->
        %Outcome{
          status: :failed,
          failures: failures,
          error: "#{error}; could not relinquish remote control: #{describe(reason)}"
        }
    end
  end

  # The minimum SoC is assumed in place: a dry run does not read it.
  defp would_write(decision) do
    read = fn _address, 1 -> {:ok, [Reading.min_soc_pct()]} end

    write = fn op ->
      send(self(), {__MODULE__, op})
      :ok
    end

    :ok = Client.apply_control(read, write, decision.target_w, Reading.min_soc_pct())
    collect([])
  end

  defp collect(ops) do
    receive do
      {__MODULE__, op} -> collect([op | ops])
    after
      0 -> Enum.reverse(ops)
    end
  end

  defp describe(reason), do: inspect(reason)
end
