defmodule Ziwoas.Mqtt do
  @moduledoc """
  The collector's MQTT connections (Tortoise311, MQTT 3.1.1, QoS 0). Tortoise
  reconnects by itself with exponential backoff (`@backoff`, 1 s to 60 s), so a
  connection is just a supervised child.

  Client ids are fixed per component (`ziwoas-phoenix-<component>`); the broker
  drops an older session that reuses an id, so two Phoenix instances must not share
  a broker.

  The web side's commands (plug switches, lamp commands) share one connection,
  `command_client_id/0`, started by `Ziwoas.Collector`.
  """
  @backoff [min_interval: 1_000, max_interval: 60_000]
  @publish_timeout_ms 5_000
  @command_client_id "ziwoas-phoenix-command"

  @doc "The client id of the command connection."
  def command_client_id, do: @command_client_id

  @doc "The child spec of one connection; `subscriptions` are topic filters (QoS 0)."
  @spec connection_spec(String.t(), map, {module, list}, [String.t()]) :: Supervisor.child_spec()
  def connection_spec(client_id, %{host: host, port: port}, handler, subscriptions \\ []) do
    opts = [
      client_id: client_id,
      server: {Tortoise311.Transport.Tcp, host: String.to_charlist(host), port: port},
      handler: handler,
      subscriptions: Enum.map(subscriptions, &{&1, 0}),
      backoff: @backoff
    ]

    Supervisor.child_spec({Tortoise311.Connection, opts}, id: {__MODULE__, client_id})
  end

  @doc """
  Publishes `payload` on `topic` (QoS 0, `retain:` as given); returns
  `{:error, reason}` while the broker is unreachable.
  """
  @spec publish(String.t(), String.t(), iodata, keyword) :: :ok | {:error, term}
  def publish(client_id, topic, payload, opts \\ []) do
    retain = Keyword.get(opts, :retain, false)

    case recorder() do
      nil ->
        Tortoise311.publish(client_id, topic, payload,
          qos: 0,
          retain: retain,
          timeout: Keyword.get(opts, :timeout, @publish_timeout_ms)
        )

      record when is_function(record, 4) ->
        record.(client_id, topic, IO.iodata_to_binary(payload), retain)

      record ->
        record.(client_id, topic, IO.iodata_to_binary(payload))
    end
  end

  # Tests hand publishes to a recorder instead of the broker through
  # `config :ziwoas, mqtt_recorder: {module, function}`: a 0-arity function that answers
  # the recorder or `nil` (`Ziwoas.TestMqtt` in test/support). The application never
  # sets it. A recorder takes `(client_id, topic, payload)` or, with arity 4, `retain`
  # too, and returns what `publish/4` returns.
  defp recorder do
    case Application.get_env(:ziwoas, :mqtt_recorder) do
      nil -> nil
      {module, function} -> apply(module, function, [])
    end
  end
end
