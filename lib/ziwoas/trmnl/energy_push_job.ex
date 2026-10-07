defmodule Ziwoas.Trmnl.EnergyPushJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Clock
  alias Ziwoas.Trmnl.{EnergyPayload, Push}

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)

    Push.run(:energy, config.trmnl.energy_webhook_url, fn ->
      EnergyPayload.build(config, Clock.now())
    end)
  end
end
