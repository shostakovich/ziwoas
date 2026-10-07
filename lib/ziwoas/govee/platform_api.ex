defmodule Ziwoas.Govee.PlatformApi do
  @moduledoc """
  Govee's documented, API-key-only cloud API. The status code lives in the JSON
  body, not in HTTP's. Every call returns `{:ok, value}` or `{:error, message}`.
  Every call counts against Govee's daily request quota.

  `api` is `%{key: api_key, req: keyword}`; `req` are extra Req options
  (`Ziwoas.Http`); tests pass `plug:`.
  """
  @base "https://openapi.api.govee.com"

  @type api :: %{key: String.t(), req: keyword}

  @spec new(String.t(), keyword) :: api
  def new(api_key, req \\ []), do: %{key: api_key, req: req}

  @spec devices(api) :: {:ok, [map]} | {:error, String.t()}
  def devices(api) do
    with {:ok, body} <- request(api, :get, "/router/api/v1/user/devices", nil),
         do: {:ok, List.wrap(body["data"])}
  end

  @doc "The capability states of a lamp, flattened to `%{instance => value}`."
  @spec state(api, String.t(), String.t()) :: {:ok, map} | {:error, String.t()}
  def state(api, sku, device) do
    with {:ok, body} <-
           request(api, :post, "/router/api/v1/device/state", %{"sku" => sku, "device" => device}),
         do: {:ok, flatten_state(body)}
  end

  @doc "A state response's capabilities as `%{instance => value}` (later instances win)."
  @spec flatten_state(map) :: map
  def flatten_state(body) do
    caps = get_in(body, ["payload", "capabilities"]) || []

    Enum.reduce(caps, %{}, fn cap, acc ->
      Map.put(acc, cap["instance"], get_in(cap, ["state", "value"]))
    end)
  end

  @spec scenes(api, String.t(), String.t()) :: {:ok, [map]} | {:error, String.t()}
  def scenes(api, sku, device) do
    with {:ok, body} <-
           request(api, :post, "/router/api/v1/device/scenes", %{"sku" => sku, "device" => device}) do
      options =
        case get_in(body, ["payload", "capabilities"]) do
          [first | _] when is_map(first) -> get_in(first, ["parameters", "options"])
          _ -> nil
        end

      {:ok, List.wrap(options)}
    end
  end

  @doc "Switches a capability (`sku:, device:, type:, instance:, value:`)."
  @spec control(api, keyword) :: {:ok, true} | {:error, String.t()}
  def control(api, opts) do
    payload = %{
      "sku" => opts[:sku],
      "device" => opts[:device],
      "capability" => %{
        "type" => opts[:type],
        "instance" => opts[:instance],
        "value" => opts[:value]
      }
    }

    with {:ok, _body} <- request(api, :post, "/router/api/v1/device/control", payload),
         do: {:ok, true}
  end

  defp request(api, method, path, payload) do
    body =
      if payload,
        do: JSON.encode!(%{"requestId" => uuid(), "payload" => payload})

    req =
      Ziwoas.Http.new(
        __MODULE__,
        Keyword.merge(
          [
            method: method,
            url: @base <> path,
            headers: [{"govee-api-key", api.key}, {"content-type", "application/json"}],
            body: body,
            retry: false,
            connect_options: [timeout: 5_000],
            receive_timeout: 10_000
          ],
          api.req
        )
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> check(body)
      {:ok, %Req.Response{status: status}} -> {:error, "HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp check(body) do
    case JSON.decode(body) do
      {:ok, %{} = parsed} ->
        if parsed["code"] in [200, "200"],
          do: {:ok, parsed},
          else: {:error, "code #{parsed["code"]}: #{parsed["message"] || parsed["msg"]}"}

      _ ->
        {:error, "invalid JSON"}
    end
  end

  defp uuid do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format("~8.16.0b-~4.16.0b-4~3.16.0b-~2.16.0b~2.16.0b-~12.16.0b", [
      a,
      b,
      c,
      Bitwise.bor(0x80, Bitwise.bsr(d, 8)),
      Bitwise.band(d, 0xFF),
      e
    ])
    |> IO.iodata_to_binary()
  end
end
