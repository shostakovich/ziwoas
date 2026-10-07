defmodule Ziwoas.Scheduler.Runner do
  @moduledoc """
  One recurring job: sleeps until its schedule falls due (`Process.send_after/3`),
  runs the job in this process, sleeps again. A run that overlaps the next due
  instant skips it; nothing is made up after downtime.

  Options: `:id`, `:schedule` (text or `Schedule`), `:job` (a
  `Ziwoas.Scheduler.Job`), `:zone`; for tests `:clock` (0-arity, a UTC `DateTime`) and `:timer`
  (`Process.send_after/3`'s shape).
  """
  use GenServer

  require Logger

  alias Ziwoas.Scheduler.Schedule

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts),
    do: %{id: Keyword.fetch!(opts, :id), start: {__MODULE__, :start_link, [opts]}}

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)

    state = %{
      id: id,
      schedule: schedule(Keyword.fetch!(opts, :schedule)),
      job: Keyword.fetch!(opts, :job),
      zone: Keyword.fetch!(opts, :zone),
      clock: Keyword.get(opts, :clock, &Ziwoas.Clock.now/0),
      timer: Keyword.get(opts, :timer, &Process.send_after/3),
      due: nil
    }

    {:ok, arm(state, state.clock.())}
  end

  @impl true
  def handle_info({:due, at}, %{due: at} = state) do
    now = state.clock.()

    if DateTime.before?(now, at) do
      # The timer ran ahead of the clock: wait out the rest.
      {:noreply, arm_at(state, at, now)}
    else
      perform(state, %{at: at})
      {:noreply, arm(state, latest(at, state.clock.()))}
    end
  end

  def handle_info({:due, _stale}, state), do: {:noreply, state}

  defp perform(state, context) do
    state.job.perform(context)
  rescue
    error ->
      Logger.error(
        "scheduler: #{state.id} failed: " <> Exception.format(:error, error, __STACKTRACE__)
      )
  catch
    kind, reason ->
      Logger.error("scheduler: #{state.id} #{kind}: #{inspect(reason)}")
  end

  defp arm(state, from),
    do: arm_at(state, Schedule.next_after(state.schedule, from, state.zone), from)

  defp arm_at(state, due, now) do
    state.timer.(self(), {:due, due}, max(DateTime.diff(due, now, :millisecond), 0))
    %{state | due: due}
  end

  defp latest(a, b), do: if(DateTime.after?(b, a), do: b, else: a)

  defp schedule(%Schedule{} = schedule), do: schedule
  defp schedule(text), do: Schedule.parse!(text)
end
