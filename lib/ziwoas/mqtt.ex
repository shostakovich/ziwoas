defmodule Ziwoas.Mqtt do
  @moduledoc """
  The collector's MQTT connections (Tortoise311, MQTT 3.1.1, QoS 0 like Rails' `mqtt`
  gem). Tortoise reconnects by itself with exponential backoff (`@backoff`, 1 s to
  60 s like Rails' `MqttRouter`), so a connection is just a supervised child.

  Client ids are fixed per component (`ziwoas-phoenix-<component>`); the broker
  drops an older session that reuses an id, so two Phoenix instances must not share
  a broker. Rails' clients use random ids and never collide with these.

  Publishing is a device write: `publish/5` calls `Ziwoas.Ownership.ensure_owner!/1`
  first, so a task in shadow mode cannot reach the shared broker.

  The web side's commands (plug switches, lamp commands: Rails' `Switching::Commander`
  and `Govees::Commander`, which open a connection per command) share one
  connection, `command_client_id/0`, started while `switching` or `lights` is
  Phoenix's (`Ziwoas.Collector`).
  """
  alias Ziwoas.Ownership

  @backoff [min_interval: 1_000, max_interval: 60_000]
  @publish_timeout_ms 5_000
  @command_client_id "ziwoas-phoenix-command"
  @recorder_key {__MODULE__, :recorder}

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
  Publishes `payload` on `topic` for `task` (QoS 0, `retain:` as given). Raises
  `Ziwoas.Ownership.NotOwnerError` unless Phoenix owns the task; returns
  `{:error, reason}` while the broker is unreachable.
  """
  @spec publish(Ownership.task(), String.t(), String.t(), iodata, keyword) :: :ok | {:error, term}
  def publish(task, client_id, topic, payload, opts \\ []) do
    Ownership.ensure_owner!(task)

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

  @doc """
  Test support (`config :ziwoas, mqtt_recorder: true`: tests and the golden master):
  `publish/5` in this process and the processes it starts hands `(client_id, topic,
  payload)` — or, to a 4-arity `fun`, `(client_id, topic, payload, retain)` — to `fun`
  instead of the broker, after the ownership check, and returns what `fun` returns
  (`:ok` or `{:error, reason}`).
  """
  @spec record(
          (String.t(), String.t(), binary -> :ok | {:error, term})
          | (String.t(), String.t(), binary, boolean -> :ok | {:error, term})
        ) :: :ok
  def record(fun) when is_function(fun, 3) or is_function(fun, 4) do
    Process.put(@recorder_key, fun)
    :ok
  end

  defp recorder do
    if Application.get_env(:ziwoas, :mqtt_recorder, false) do
      Enum.find_value([self() | Ziwoas.Repo.test_lineage()], fn
        pid when pid == self() ->
          Process.get(@recorder_key)

        pid ->
          case Process.info(pid, :dictionary) do
            {:dictionary, dictionary} ->
              with {_key, fun} <- List.keyfind(dictionary, @recorder_key, 0), do: fun

            nil ->
              nil
          end
      end)
    end
  end
end
