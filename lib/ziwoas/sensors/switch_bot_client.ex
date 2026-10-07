defmodule Ziwoas.Sensors.SwitchBotClient do
  @moduledoc false
  alias Ziwoas.Config.Switchbot
  alias Ziwoas.Http

  @base_url "https://api.switch-bot.com"
  @timeout_ms 4_000

  @type status :: %{
          temperature: number | nil,
          humidity: number | nil,
          co2: number | nil,
          battery_pct: number | nil,
          firmware_version: String.t() | nil,
          raw: map
        }

  @type reason ::
          {:http_status, pos_integer}
          | {:api_error, term, String.t() | nil}
          | {:invalid_json, term}
          | :unexpected_body
          | Exception.t()

  @spec device_status(Switchbot.t(), String.t()) :: {:ok, status} | {:error, reason}
  def device_status(%Switchbot{} = auth, device_id) do
    with {:ok, json} <- get_json(auth, "/v1.1/devices/#{device_id}/status") do
      {:ok, normalize_status(Map.get(json, "body", %{}))}
    end
  end

  @spec list_all_devices(Switchbot.t()) :: {:ok, [map]} | {:error, reason}
  def list_all_devices(%Switchbot{} = auth) do
    with {:ok, json} <- get_json(auth, "/v1.1/devices") do
      devices =
        json
        |> Map.get("body", %{})
        |> Map.get("deviceList", [])
        |> Enum.map(&%{id: &1["deviceId"], name: &1["deviceName"], device_type: &1["deviceType"]})

      {:ok, devices}
    end
  end

  defp get_json(auth, path) do
    request =
      Http.new(__MODULE__,
        base_url: @base_url,
        url: path,
        headers: signed_headers(auth),
        retry: false,
        connect_options: [timeout: @timeout_ms],
        receive_timeout: @timeout_ms
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> check(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp check(body) do
    case JSON.decode(body) do
      {:ok, %{"statusCode" => 100} = json} ->
        {:ok, json}

      {:ok, %{} = json} ->
        {:error, {:api_error, json["statusCode"], json["message"]}}

      {:ok, _other} ->
        {:error, :unexpected_body}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  # Wall-clock milliseconds, not Ziwoas.Clock: the API checks the signature's age.
  defp signed_headers(%Switchbot{token: token, secret: secret}) do
    t = Integer.to_string(System.os_time(:millisecond))
    nonce = Ecto.UUID.generate()
    sign = :crypto.mac(:hmac, :sha256, secret, token <> t <> nonce) |> Base.encode64()

    [
      {"authorization", token},
      {"t", t},
      {"nonce", nonce},
      {"sign", sign},
      {"content-type", "application/json"}
    ]
  end

  defp normalize_status(body) do
    %{
      temperature: body["temperature"],
      humidity: body["humidity"],
      co2: body["CO2"],
      battery_pct: body["battery"],
      firmware_version: body["version"],
      raw: body
    }
  end
end
