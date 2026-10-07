defmodule Ziwoas.Scheduler.Job do
  @moduledoc """
  What a recurring job implements. `Ziwoas.Scheduler` calls `perform/1` each time
  the job's schedule falls due:

      defmodule Ziwoas.Weather.CurrentJob do
        @behaviour Ziwoas.Scheduler.Job

        @impl true
        def perform(context) do
          config = Ziwoas.Scheduler.Job.config(context)
          config.location |> fetch() |> upsert(context.at)
        end
      end

  The context carries the due instant `:at`. The return value is ignored, an
  exception is logged and the next run comes as scheduled.
  """

  @type context :: %{
          required(:at) => DateTime.t(),
          optional(:config) => Ziwoas.Config.t()
        }

  @callback perform(context) :: any

  @doc """
  The device config a run works with: `Ziwoas.Config.app_config/0`, or the
  context's `:config` (tests).
  """
  @spec config(map) :: Ziwoas.Config.t()
  def config(context), do: Map.get_lazy(context, :config, &Ziwoas.Config.app_config/0)
end
