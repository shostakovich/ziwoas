defmodule Ziwoas.Govee.CommandHandler do
  @moduledoc """
  The Tortoise311 handler of the bridge's `ziwoas-phoenix-govee` connection: hands
  every `govees/<key>/set` to `Ziwoas.Govee.Bridge`. Only started as owner — a
  shadow bridge consumes no command.
  """
  use Tortoise311.Handler

  require Logger

  @impl true
  def init([bridge]), do: {:ok, bridge}

  @impl true
  def connection(status, bridge) do
    Logger.info("Govee bridge command connection #{status}")
    {:ok, bridge}
  end

  @impl true
  def handle_message(["govees", key, "set"], payload, bridge) do
    send(bridge, {:set, key, payload})
    {:ok, bridge}
  end

  def handle_message(_levels, _payload, bridge), do: {:ok, bridge}
end
