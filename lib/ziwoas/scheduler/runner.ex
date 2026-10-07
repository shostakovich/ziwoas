defmodule Ziwoas.Scheduler.Runner do
  @moduledoc """
  One recurring job: sleeps until its schedule falls due (`Process.send_after/3`),
  runs the job in this process when its task is not `:rails`, sleeps again. A run
  that overlaps the next due instant skips it; nothing is made up after downtime,
  as with Solid Queue's recurring tasks.

  Options: `:id`, `:task`, `:schedule` (text or `Schedule`), `:job` (a
  `Ziwoas.Scheduler.Job`), `:zone`, `:shadow_offset` (seconds after each due
  instant while the task runs in `:shadow`/`:dry_run`, so a shadow does not poll a
  device the moment Rails does; default 0); for tests `:clock` (0-arity, a UTC
  `DateTime`) and `:timer` (`Process.send_after/3`'s shape).

  As owner a run first needs the task's lease (`Ziwoas.Lease`): while Rails holds
  it the run is skipped and logged as an error.
  """
  use GenServer

  require Logger

  alias Ziwoas.Ownership
  alias Ziwoas.Scheduler.Schedule

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts),
    do: %{id: Keyword.fetch!(opts, :id), start: {__MODULE__, :start_link, [opts]}}

  @impl true
  def init(opts) do
    state = %{
      id: Keyword.fetch!(opts, :id),
      task: task!(Keyword.fetch!(opts, :task)),
      schedule: schedule(Keyword.fetch!(opts, :schedule)),
      job: Keyword.fetch!(opts, :job),
      zone: Keyword.fetch!(opts, :zone),
      shadow_offset: Keyword.get(opts, :shadow_offset, 0),
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
      run(state, at)
      {:noreply, arm(state, latest(at, state.clock.()))}
    end
  end

  def handle_info({:due, _stale}, state), do: {:noreply, state}

  defp run(state, at) do
    case Ownership.mode(state.task) do
      :rails ->
        :skipped

      :phoenix ->
        if Ziwoas.Lease.held?(state.task),
          do: perform(state, %{task: state.task, mode: :phoenix, at: at}),
          else: refuse(state)

      mode ->
        perform(state, %{task: state.task, mode: mode, at: at})
    end
  rescue
    error -> Logger.error("scheduler: #{state.id}: #{Exception.message(error)}")
  end

  defp refuse(state) do
    Logger.error(
      "scheduler: #{state.id} skipped: #{Ziwoas.Lease.holder(state.task) || "nobody"} " <>
        "holds the lease of #{state.task}"
    )

    :refused
  end

  defp perform(state, context) do
    state.job.perform(context)
  rescue
    error ->
      Logger.error(
        "scheduler: #{state.id} (#{context.mode}) failed: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )
  catch
    kind, reason ->
      Logger.error("scheduler: #{state.id} (#{context.mode}) #{kind}: #{inspect(reason)}")
  end

  defp arm(state, from) do
    offset =
      if Ownership.mode(state.task) in [:shadow, :dry_run], do: state.shadow_offset, else: 0

    due =
      state.schedule
      |> Schedule.next_after(DateTime.add(from, -offset), state.zone)
      |> DateTime.add(offset)

    arm_at(state, due, from)
  end

  defp arm_at(state, due, now) do
    state.timer.(self(), {:due, due}, max(DateTime.diff(due, now, :millisecond), 0))
    %{state | due: due}
  end

  defp latest(a, b), do: if(DateTime.after?(b, a), do: b, else: a)

  defp schedule(%Schedule{} = schedule), do: schedule
  defp schedule(text), do: Schedule.parse!(text)

  defp task!(task) do
    Ownership.mode(task, Ownership.all_rails())
    task
  end
end
