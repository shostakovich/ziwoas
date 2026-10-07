defmodule Ziwoas.Trmnl.EnergyPushJob do
  @moduledoc "Pushes the TRMNL energy widget (`push_trmnl_widget`, every 15 minutes)."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Clock
  alias Ziwoas.Trmnl.{EnergyPayload, Push}

  @impl true
  def perform(context) do
    config = Ziwoas.Scheduler.Job.config(context)

    Push.run(:energy, config.trmnl.energy_webhook_url, fn ->
      EnergyPayload.build(config, Clock.now())
    end)
  end
end
