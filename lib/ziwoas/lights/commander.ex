defmodule Ziwoas.Lights.Commander do
  @moduledoc """
  The web side's choke point for lamp commands (`Govees::Commander`): one `set` verb
  on `govees/<key>/set`, as Ruby's `JSON.generate` writes it. The Govee bridge does
  the rest (routing, optimistic state, reconcile).

  As owner of `lights` it publishes over the command connection
  (`Ziwoas.Mqtt.publish/5` checks ownership itself); in a dry run it logs the
  would-be message; for `:rails` it raises `Ziwoas.Ownership.NotOwnerError`.
  """
  require Logger

  alias Ziwoas.{Mqtt, Ownership, RubyJSON}
  alias Ziwoas.Govee.Messages

  @task :lights

  @doc "Sends one verb (`Ziwoas.Govee.Messages.set/1`'s tuples) to the lamp `key`."
  @spec publish(String.t(), tuple) :: :ok | {:error, String.t()}
  def publish(key, verb) do
    topic = "govees/#{key}/set"
    payload = RubyJSON.generate!(Messages.set_wire(verb))

    if Ownership.mode(@task) == :dry_run do
      Logger.info("lights dry run: would publish #{topic} #{payload}")
      :ok
    else
      case Mqtt.publish(@task, Mqtt.command_client_id(), topic, payload) do
        :ok -> :ok
        {:error, reason} -> {:error, "MQTT publish for '#{key}' failed: #{inspect(reason)}"}
      end
    end
  end
end
