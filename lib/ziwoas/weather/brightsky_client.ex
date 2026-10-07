defmodule Ziwoas.Weather.BrightskyClient do
  @moduledoc """
  Bright Sky, the DWD's open weather data: the current
  observation and the hours of a date, as `weather_records` attributes. Retries
  twice on a 5xx or a transport error, 0.5 s and 1 s apart; a date answered with
  404 is past the end of the forecast (`:range_end`). Other failures raise `Error`.
  """
  alias Ziwoas.{Clock, Http, Location}
  alias Ziwoas.Weather.Icon

  @base_url "https://api.brightsky.dev"
  @retries 2
  @timeout_ms 5_000

  defmodule Error do
    @moduledoc "Bright Sky answered with an error, garbage or not at all."
    defexception [:message]
  end

  @type row :: %{atom => term}

  @spec current_weather(Location.t()) :: row
  def current_weather(%Location{} = location) do
    location
    |> get_json!("/current_weather", [])
    |> Map.fetch!("weather")
    |> normalize_current(location)
  end

  @spec weather_for_date(Location.t(), Date.t()) :: [row] | :range_end
  def weather_for_date(%Location{} = location, %Date{} = date) do
    location
    |> get_json!("/weather", date: Date.to_iso8601(date))
    |> Map.get("weather", [])
    |> Enum.map(&normalize_hourly(&1, location))
  rescue
    error in Error ->
      if error.message =~ "404", do: :range_end, else: reraise(error, __STACKTRACE__)
  end

  defp get_json!(location, path, params) do
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
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> decode!(body)
      {:ok, %Req.Response{status: status}} -> raise Error, "Bright Sky HTTP #{status}"
      {:error, exception} -> raise Error, Exception.message(exception)
    end
  end

  defp retry?(_request, %Req.Response{status: status}), do: status >= 500
  defp retry?(_request, _exception), do: true

  defp retry_delay(count),
    do: Application.get_env(:ziwoas, :brightsky_retry_base_ms, 500) * (count + 1)

  defp decode!(body) do
    case JSON.decode(body) do
      {:ok, json} when is_map(json) -> json
      {:ok, _other} -> raise Error, "Bright Sky answered no JSON object"
      {:error, reason} -> raise Error, "Bright Sky JSON: #{inspect(reason)}"
    end
  end

  defp normalize_current(row, location) do
    timestamp = timestamp!(row)

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
      daytime: Icon.daytime_for(row["icon"], timestamp, location)
    }
  end

  defp normalize_hourly(row, location) do
    timestamp = timestamp!(row)

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
      daytime: Icon.daytime_for(row["icon"], timestamp, location)
    }
  end

  defp timestamp!(row), do: row |> Map.fetch!("timestamp") |> Clock.parse!()
end
