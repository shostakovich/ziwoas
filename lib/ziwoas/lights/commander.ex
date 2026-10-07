defmodule Ziwoas.Lights.Commander do
  @moduledoc """
  The web side's choke point for lamp commands: one `set` verb as JSON on
  `govees/<key>/set`, over the command connection. The Govee bridge does the
  rest (routing, optimistic state, reconcile).
  """
  alias Ziwoas.Govee.Messages
  alias Ziwoas.Mqtt

  @doc "Sends one verb (`Ziwoas.Govee.Messages.set/1`'s tuples) to the lamp `key`."
  @spec publish(String.t(), tuple) :: :ok | {:error, String.t()}
  def publish(key, verb) do
    payload = JSON.encode!(Messages.set_wire(verb))

    case Mqtt.publish(Mqtt.command_client_id(), "govees/#{key}/set", payload) do
      :ok -> :ok
      {:error, reason} -> {:error, "MQTT publish for '#{key}' failed: #{inspect(reason)}"}
    end
  end
end
