defmodule Ziwoas.Mqtt do
  @moduledoc "The broker drops an older session reusing a client id, so two instances must not share a broker."
  @backoff [min_interval: 1_000, max_interval: 60_000]
  @command_client_id "ziwoas-phoenix-command"
  @publisher Application.compile_env(:ziwoas, :mqtt_publisher, Ziwoas.Mqtt.Broker)

  @callback publish(client_id :: String.t(), topic :: String.t(), payload :: binary, keyword) ::
              :ok | {:error, term}

  def command_client_id, do: @command_client_id

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

  @spec publish(String.t(), String.t(), iodata, keyword) :: :ok | {:error, term}
  def publish(client_id, topic, payload, opts \\ []),
    do: @publisher.publish(client_id, topic, IO.iodata_to_binary(payload), opts)

  defmodule Broker do
    @moduledoc false
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
