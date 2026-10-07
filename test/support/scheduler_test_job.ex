defmodule Ziwoas.Scheduler.TestJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  @impl true
  def perform(opts) do
    send(List.last(Ziwoas.TestProcess.lineage()), {:performed, opts})
    :ok
  end
end

defmodule Ziwoas.Scheduler.FailingTestJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Scheduler.TestJob

  @impl true
  def perform(opts) do
    TestJob.perform(opts)
    raise "job failed"
  end
end
