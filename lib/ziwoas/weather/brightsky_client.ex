defmodule Ziwoas.Weather.BrightskyClient do
  @moduledoc false
  alias Ziwoas.{Clock, Http, Location, Weather}

  @base_url "https://api.brightsky.dev"
  @retries 2
  @timeout_ms 5_000
  @retry_base_ms Application.compile_env(:ziwoas, :brightsky_retry_base_ms, 500)

  @type row :: %{atom => term}
  @type reason ::
          {:http_status, pos_integer}
          | {:invalid_json, term}
          | :unexpected_body
          | {:invalid_timestamp, term}
          | Exception.t()

  @spec current_weather(Location.t()) :: {:ok, row} | {:error, reason}
  def current_weather(%Location{} = location) do
    with {:ok, %{"weather" => %{} = row}} <- get_json(location, "/current_weather", []),
         {:ok, timestamp} <- timestamp(row) do
      {:ok, normalize_current(row, timestamp, location)}
    else
      {:ok, _json} -> {:error, :unexpected_body}
      error -> error
    end
  end

  @doc "A date past the end of the forecast is answered with `{:http_status, 404}`."
  @spec weather_for_date(Location.t(), Date.t()) :: {:ok, [row]} | {:error, reason}
  def weather_for_date(%Location{} = location, %Date{} = date) do
    case get_json(location, "/weather", date: Date.to_iso8601(date)) do
      {:ok, %{"weather" => rows}} when is_list(rows) -> normalize_hours(rows, location)
      {:ok, json} when not is_map_key(json, "weather") -> {:ok, []}
      {:ok, _json} -> {:error, :unexpected_body}
      error -> error
    end
  end

  defp normalize_hours(rows, location) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case timestamp(row) do
        {:ok, timestamp} -> {:cont, {:ok, [normalize_hourly(row, timestamp, location) | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp get_json(location, path, params) do
    params = [lat: location.lat, lon: location.lon] ++ params

    request =
      Http.new(__MODULE__,
        base_url: @base_url,
        url: path,
        params: params,
        retry: &retry?/2,
        max_retries: @retries,
        retry_delay: &retry_delay/1,
        retry_log_level: :warning,
        connect_options: [timeout: @timeout_ms],
        receive_timeout: @timeout_ms
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> decode(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp retry?(_request, %Req.Response{status: status}), do: status >= 500
  defp retry?(_request, _exception), do: true

  defp retry_delay(count),
    do: @retry_base_ms * (count + 1)

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, json} when is_map(json) -> {:ok, json}
      {:ok, _other} -> {:error, :unexpected_body}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp normalize_current(row, timestamp, location) do
    %{
      timestamp: timestamp,
      source_id: row["source_id"],
      precipitation: row["precipitation_10"],
      pressure_msl: row["pressure_msl"],
      sunshine: nil,
      temperature: row["temperature"],
      wind_direction: row["wind_direction_10"],
      wind_speed: row["wind_speed_10"],
      cloud_cover: row["cloud_cover"],
      dew_point: row["dew_point"],
      relative_humidity: row["relative_humidity"],
      visibility: row["visibility"],
      wind_gust_direction: row["wind_gust_direction_10"],
      wind_gust_speed: row["wind_gust_speed_10"],
      condition: row["condition"],
      precipitation_probability: nil,
      precipitation_probability_6h: nil,
      solar: row["solar_10"],
      icon: row["icon"],
      daytime: Weather.daytime_for(row["icon"], timestamp, location)
    }
  end

  defp normalize_hourly(row, timestamp, location) do
    %{
      timestamp: timestamp,
      source_id: row["source_id"],
      precipitation: row["precipitation"],
      pressure_msl: row["pressure_msl"],
      sunshine: row["sunshine"],
      temperature: row["temperature"],
      wind_direction: row["wind_direction"],
      wind_speed: row["wind_speed"],
      cloud_cover: row["cloud_cover"],
      dew_point: row["dew_point"],
      relative_humidity: row["relative_humidity"],
      visibility: row["visibility"],
      wind_gust_direction: row["wind_gust_direction"],
      wind_gust_speed: row["wind_gust_speed"],
      condition: row["condition"],
      precipitation_probability: row["precipitation_probability"],
      precipitation_probability_6h: row["precipitation_probability_6h"],
      solar: row["solar"],
      icon: row["icon"],
      daytime: Weather.daytime_for(row["icon"], timestamp, location)
    }
  end

  defp timestamp(%{"timestamp" => text}) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, instant, _offset} -> {:ok, Clock.parse!(instant)}
      {:error, _reason} -> {:error, {:invalid_timestamp, text}}
    end
  end

  defp timestamp(row), do: {:error, {:invalid_timestamp, row["timestamp"]}}
end
