defmodule Ziwoas.Mqtt do
  @moduledoc """
  The collector's MQTT connections (Tortoise311, MQTT 3.1.1, QoS 0). Tortoise
  reconnects by itself with exponential backoff (`@backoff`, 1 s to 60 s), so a
  connection is just a supervised child.

  Client ids are fixed per component (`ziwoas-phoenix-<component>`); the broker
  drops an older session that reuses an id, so two Phoenix instances must not share
  a broker.

  The web side's plug switches share one connection,
  `command_client_id/0`, started by `Ziwoas.Collector`.

  `publish/4` goes through `config :ziwoas, :mqtt_publisher`, a module with
  `publish/4` (this behaviour), fixed at compile time: `Ziwoas.Mqtt.Broker`, in
  tests `Ziwoas.TestMqtt` (test/support), which can record publishes.
  """
  @backoff [min_interval: 1_000, max_interval: 60_000]
  @command_client_id "ziwoas-phoenix-command"
  @publisher Application.compile_env(:ziwoas, :mqtt_publisher, Ziwoas.Mqtt.Broker)

  @callback publish(client_id :: String.t(), topic :: String.t(), payload :: binary, keyword) ::
              :ok | {:error, term}

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
  Publishes `payload` on `topic` (QoS 0, not retained); returns
  `{:error, reason}` while the broker is unreachable.
  """
  @spec publish(String.t(), String.t(), iodata, keyword) :: :ok | {:error, term}
  def publish(client_id, topic, payload, opts \\ []),
    do: @publisher.publish(client_id, topic, IO.iodata_to_binary(payload), opts)

  defmodule Broker do
    @moduledoc "Publishes through the Tortoise311 connection `client_id`."
    @behaviour Ziwoas.Mqtt

    @publish_timeout_ms 5_000

    @impl true
    def publish(client_id, topic, payload, opts) do
      Tortoise311.publish(client_id, topic, payload,
        qos: 0,
        retain: false,
        timeout: Keyword.get(opts, :timeout, @publish_timeout_ms)
      )
    end
  end
end
