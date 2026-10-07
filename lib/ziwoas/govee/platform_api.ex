defmodule Ziwoas.Govee.PlatformApi do
  @moduledoc "Govee's status code lives in the JSON body, not in HTTP's."
  @base "https://openapi.api.govee.com"

  import Bitwise

  alias Ziwoas.Govee.Types

  @type api :: %{key: String.t(), req: keyword}
  @type error ::
          {:http_status, pos_integer} | {:api, term, term} | :invalid_json | Exception.t()

  @spec new(String.t(), keyword) :: api
  def new(api_key, req \\ []), do: %{key: api_key, req: req}

  @spec devices(api) :: {:ok, [map]} | {:error, error}
  def devices(api) do
    with {:ok, body} <- request(api, :get, "/router/api/v1/user/devices", nil),
         do: {:ok, List.wrap(body["data"])}
  end

  @spec state(api, String.t(), String.t()) :: {:ok, map} | {:error, error}
  def state(api, sku, device) do
    with {:ok, body} <-
           request(api, :post, "/router/api/v1/device/state", %{"sku" => sku, "device" => device}),
         do: {:ok, flatten_state(body)}
  end

  @spec flatten_state(map) :: map
  def flatten_state(body) do
    caps = get_in(body, ["payload", "capabilities"]) || []

    Enum.reduce(caps, %{}, fn cap, acc ->
      Map.put(acc, cap["instance"], get_in(cap, ["state", "value"]))
    end)
  end

  @spec scenes(api, String.t(), String.t()) :: {:ok, [map]} | {:error, error}
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

  @doc "An unreachable lamp is never on, whatever the cloud remembers."
  @spec telemetry(map, [String.t()]) :: {:ok, map} | :error
  def telemetry(map, zone_keys) do
    online = Map.get(map, "online", true)
    reachable = online === true or online == 1

    telemetry = %{
      on: reachable and to_int(map["powerSwitch"]) == 1,
      reachable: reachable
    }

    with {:ok, telemetry} <-
           optional(telemetry, map, "brightness", :brightness, &Types.brightness/1),
         {:ok, telemetry} <- color_or_kelvin(telemetry, map, to_int(map["colorRgb"])) do
      zones =
        for zone <- zone_keys,
            (value = map[zone]) not in [nil, ""],
            into: %{},
            do: {zone, to_int(value) == 1}

      {:ok, if(zones == %{}, do: telemetry, else: Map.put(telemetry, :zone_states, zones))}
    end
  end

  defp color_or_kelvin(telemetry, _map, rgb) when rgb > 0,
    do:
      {:ok,
       Map.put(telemetry, :color, %{
         r: rgb >>> 16 &&& 0xFF,
         g: rgb >>> 8 &&& 0xFF,
         b: rgb &&& 0xFF
       })}

  defp color_or_kelvin(telemetry, map, _rgb) do
    if to_int(map["colorTemperatureK"]) > 0,
      do: optional(telemetry, map, "colorTemperatureK", :color_temp_k, &Types.kelvin/1),
      else: {:ok, telemetry}
  end

  defp optional(acc, map, key, field, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> with {:ok, coerced} <- fun.(value), do: {:ok, Map.put(acc, field, coerced)}
      :error -> {:ok, acc}
    end
  end

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  defp to_int(_value), do: 0

  @spec control(api, keyword) :: {:ok, true} | {:error, error}
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
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp check(body) do
    case JSON.decode(body) do
      {:ok, %{} = parsed} ->
        if parsed["code"] in [200, "200"],
          do: {:ok, parsed},
          else: {:error, {:api, parsed["code"], parsed["message"] || parsed["msg"]}}

      _ ->
        {:error, :invalid_json}
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
