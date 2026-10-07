defmodule Ziwoas.Scheduler.Job do
  @moduledoc """
  What a recurring job implements. `Ziwoas.Scheduler` calls `perform/1` only while
  the job's task is not `:rails`, with the mode in effect:

      defmodule Ziwoas.Weather.CurrentJob do
        @behaviour Ziwoas.Scheduler.Job

        @impl true
        def perform(%{task: task}) do
          records = fetch()                                  # reading is always fine
          Ziwoas.Repo.write(task, fn -> upsert(records) end) # main or shadow by mode
        end
      end

  `:shadow`/`:dry_run` must neither send to devices nor push out nor broadcast;
  `Ziwoas.Ownership.may_write_devices?/1` tells. The return value is ignored, an
  exception is logged and the next run comes as scheduled.
  """

  @type context :: %{
          task: Ziwoas.Ownership.task(),
          mode: :shadow | :dry_run | :phoenix,
          at: DateTime.t()
        }

  @callback perform(context) :: any

  @doc """
  The device config a run works with: `Ziwoas.Config.app_config/0`, or the
  context's `:config` (tests).
  """
  @spec config(map) :: Ziwoas.Config.t()
  def config(context), do: Map.get_lazy(context, :config, &Ziwoas.Config.app_config/0)
end
