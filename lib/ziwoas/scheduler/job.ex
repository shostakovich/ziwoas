defmodule Ziwoas.Scheduler.Job do
  @moduledoc """
  What a recurring job implements. `Ziwoas.Scheduler` calls `perform/1` each time
  the job's schedule falls due, with the job's opts from `Ziwoas.Scheduler.jobs/1`
  (always `:config`) plus the due instant as `:at`:

      defmodule Ziwoas.Weather.CurrentJob do
        @behaviour Ziwoas.Scheduler.Job

        @impl true
        def perform(opts), do: opts |> Keyword.fetch!(:config) |> sync()
      end

  The return value is ignored, an exception is logged and the next run comes as
  scheduled.
  """

  @callback perform(opts :: keyword) :: any
end
