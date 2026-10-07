defmodule Ziwoas.Scheduler.TestJob do
  @moduledoc "A recurring job for tests: tells the test that started its runner about each run."
  @behaviour Ziwoas.Scheduler.Job

  @impl true
  def perform(context) do
    send(List.last(Ziwoas.Repo.test_lineage()), {:performed, context})
    :ok
  end
end

defmodule Ziwoas.Scheduler.FailingTestJob do
  @moduledoc "A recurring job for tests that reports, then raises."
  @behaviour Ziwoas.Scheduler.Job

  @impl true
  def perform(context) do
    Ziwoas.Scheduler.TestJob.perform(context)
    raise "job failed"
  end
end
