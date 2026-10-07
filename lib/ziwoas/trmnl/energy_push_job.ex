defmodule Ziwoas.Trmnl.EnergyPushJob do
  @moduledoc "Rails' `TrmnlPushJob` (`push_trmnl_widget`): the energy widget, every 15 minutes."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Clock
  alias Ziwoas.Trmnl.{EnergyPayload, Push}

  @impl true
  def perform(%{task: task} = context) do
    config = Ziwoas.Scheduler.Job.config(context)

    Push.run(task, :energy, config.trmnl.energy_webhook_url, fn ->
      EnergyPayload.build(config, Clock.now())
    end)
  end
end
