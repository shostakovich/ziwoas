defmodule Ziwoas.Scheduler.JobsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Scheduler.Schedule

  defp configured_jobs, do: Application.fetch_env!(:ziwoas, Ziwoas.Scheduler)[:jobs]

  test "every schedule parses and every job implements the behaviour" do
    for {_name, job} <- configured_jobs() do
      assert %Schedule{} = Schedule.parse!(job[:schedule])

      assert Ziwoas.Scheduler.Job in Keyword.get(
               job[:job].module_info(:attributes),
               :behaviour,
               []
             )
    end
  end
end
