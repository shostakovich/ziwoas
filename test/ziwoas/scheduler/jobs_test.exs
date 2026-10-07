defmodule Ziwoas.Scheduler.JobsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Scheduler.Schedule

  defp phoenix_jobs, do: Application.fetch_env!(:ziwoas, Ziwoas.Scheduler)[:jobs]

  test "a shadowing Solakon monitor reads out of phase with Rails'" do
    jobs = phoenix_jobs()

    assert jobs[:solakon_monitor][:shadow_offset] == 10
    assert jobs[:solakon_snapshot][:shadow_offset] == 40
    assert Enum.all?(jobs, fn {_name, job} -> job[:shadow_offset] in [nil, 10, 40] end)
  end

  test "every schedule parses and every job implements the behaviour" do
    for {_name, job} <- phoenix_jobs() do
      assert %Schedule{} = Schedule.parse!(job[:schedule])

      assert Ziwoas.Scheduler.Job in Keyword.get(
               job[:job].module_info(:attributes),
               :behaviour,
               []
             )
    end
  end
end
