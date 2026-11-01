defmodule Ziwoas.Hue.Client do
  @moduledoc """
  The Hue Bridge's local API v2. TLS is verified against the Hue root CA, and every request that
  carries the application key also against the bridge ID in the certificate's common name.
  """
  require Record

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  @root_ca_path Path.expand("../../../priv/hue/root-bridge.pem", __DIR__)
  @external_resource @root_ca_path
  @root_ca @root_ca_path
           |> File.read!()
           |> :public_key.pem_decode()
           |> then(fn [{:Certificate, der, :not_encrypted}] -> der end)

  @common_name {2, 5, 4, 3}

  @derive {Inspect, except: [:key]}
  @enforce_keys [:host, :key]
  defstruct [:host, :key, :bridge_id, req: [], open_timeout_ms: 10_000]

  @type t :: %__MODULE__{
          host: String.t(),
          key: String.t(),
          bridge_id: String.t() | nil,
          req: keyword,
          open_timeout_ms: timeout
        }
  @type error ::
          {:http_status, pos_integer}
          | {:hue, [String.t()]}
          | :invalid_json
          | :timeout
          | {:exit, term}
          | Exception.t()

  @spec new(String.t(), String.t(), keyword) :: t
  def new(host, key, req \\ []), do: %__MODULE__{host: host, key: key, req: req}

  @doc "Learns the bridge ID without sending the key; only a bridge the Hue root CA signed answers."
  @spec identify(t) :: {:ok, t} | {:error, error}
  def identify(client) do
    case request(client, :get, "/api/0/config", tls: tls(:any)) do
      {:ok, %{"bridgeid" => id}} when is_binary(id) ->
        {:ok, %{client | bridge_id: String.downcase(id)}}

      {:ok, _body} ->
        {:error, :invalid_json}

      error ->
        error
    end
  end

  @spec resources(t) :: {:ok, [map]} | {:error, error}
  def resources(client) do
    with {:ok, body} <- keyed(client, :get, "/clip/v2/resource"), do: data(body)
  end

  @doc "Gives up within 3 s, since a lamp command waits on it."
  @spec update_light(t, String.t(), map) :: :ok | {:error, error}
  def update_light(client, id, body) do
    case keyed(client, :put, "/clip/v2/resource/light/" <> id,
           json: body,
           connect_timeout: 1_000,
           receive_timeout: 2_000
         ) do
      {:ok, %{"errors" => [_ | _] = errors}} -> {:error, hue_errors(errors)}
      {:ok, _body} -> :ok
      error -> error
    end
  end

  @doc """
  The caller gets the stream's chunks as messages, see `Req.parse_message/2`. A relay process
  makes the request, so that a bridge which never answers it is given up after
  `open_timeout_ms`; Req would wait for the response headers forever.
  """
  @spec open_events(t) :: {:ok, Req.Response.t()} | {:error, error}
  def open_events(client) do
    caller = self()
    {relay, monitor} = spawn_monitor(fn -> relay_events(caller, client) end)

    receive do
      {^relay, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, reason} ->
        {:error, {:exit, reason}}
    after
      client.open_timeout_ms ->
        Process.exit(relay, :kill)
        receive do: ({:DOWN, ^monitor, :process, _pid, _reason} -> :ok)
        drop_late_answer(relay)
        {:error, :timeout}
    end
  end

  defp drop_late_answer(relay) do
    receive do
      {^relay, {:ok, response}} -> Req.cancel_async_response(response)
      {^relay, _error} -> :ok
    after
      0 -> :ok
    end
  end

  defp relay_events(caller, client) do
    Process.put(:"$callers", [caller])
    monitor = Process.monitor(caller)
    result = request_events(client)
    send(caller, {self(), result})
    with {:ok, response} <- result, do: forward(caller, monitor, response)
  end

  # Exiting abnormally takes the request process, linked to the relay, down with it.
  defp forward(caller, monitor, response) do
    receive do
      {:DOWN, ^monitor, :process, _pid, _reason} ->
        exit(:shutdown)

      message ->
        send(caller, message)
        if not ended?(response, message), do: forward(caller, monitor, response)
    end
  end

  defp ended?(response, message) do
    case Req.parse_message(response, message) do
      {:ok, parts} -> :done in parts
      {:error, _reason} -> true
      :unknown -> false
    end
  end

  defp request_events(client) do
    req =
      build(
        client,
        :get,
        "/eventstream/clip/v2",
        keyed_options(client, [{"accept", "text/event-stream"}]) ++
          [into: :self, receive_timeout: :infinity]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status} = response} ->
        Req.cancel_async_response(response)
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc false
  def verify_peer(_cert, {:bad_cert, _reason} = failure, _bridge_id), do: {:fail, failure}
  def verify_peer(_cert, {:extension, _extension}, bridge_id), do: {:unknown, bridge_id}
  def verify_peer(_cert, :valid, bridge_id), do: {:valid, bridge_id}
  def verify_peer(_cert, :valid_peer, :any), do: {:valid, :any}

  def verify_peer(cert, :valid_peer, bridge_id) do
    if common_name(cert) == bridge_id,
      do: {:valid, bridge_id},
      else: {:fail, :bridge_id_mismatch}
  end

  defp common_name(cert) do
    {:rdnSequence, rdns} =
      cert |> otp_certificate(:tbsCertificate) |> tbs_certificate(:subject)

    Enum.find_value(rdns, fn
      [{:AttributeTypeAndValue, @common_name, value}] -> value |> text() |> String.downcase()
      _attribute -> nil
    end)
  end

  defp text({_string_type, value}), do: to_string(value)
  defp text(value), do: to_string(value)

  # The bridge's certificate has no subjectAltName, so OTP's host name check would refuse it.
  defp tls(bridge_id),
    do: [
      verify: :verify_peer,
      cacerts: [@root_ca],
      server_name_indication: :disable,
      reuse_sessions: false,
      verify_fun: {&__MODULE__.verify_peer/3, bridge_id}
    ]

  defp keyed(client, method, path, opts \\ []),
    do: request(client, method, path, keyed_options(client) ++ opts)

  defp keyed_options(client, headers \\ []),
    do: [tls: tls(client.bridge_id), headers: [{"hue-application-key", client.key} | headers]]

  defp request(client, method, path, opts) do
    case Req.request(build(client, method, path, opts)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> decode(body)
      {:ok, %Req.Response{status: status, body: body}} -> {:error, failure(status, body)}
      {:error, exception} -> {:error, exception}
    end
  end

  defp build(client, method, path, opts) do
    {tls, opts} = Keyword.pop!(opts, :tls)
    {connect_timeout, opts} = Keyword.pop(opts, :connect_timeout, 5_000)

    Ziwoas.Http.new(
      __MODULE__,
      Keyword.merge(
        [
          method: method,
          url: "https://#{client.host}#{path}",
          retry: false,
          connect_options: [timeout: connect_timeout, transport_opts: tls],
          receive_timeout: 10_000
        ],
        opts ++ client.req
      )
    )
  end

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp data(%{"data" => data}) when is_list(data), do: {:ok, data}
  defp data(_body), do: {:error, :invalid_json}

  defp failure(status, body) do
    case decode(body) do
      {:ok, %{"errors" => [_ | _] = errors}} -> hue_errors(errors)
      _not_hue -> {:http_status, status}
    end
  end

  defp hue_errors(errors), do: {:hue, Enum.map(errors, & &1["description"])}
end
