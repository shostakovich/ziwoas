defmodule Ziwoas.Sensors.Sen66.Line do
  @moduledoc "One line of the SEN66 firmware's serial protocol (`ziwoas-airquality/SPEC.md`)."

  @decimals [:pm1_0, :pm2_5, :pm4_0, :pm10, :temperature, :humidity]
  @indices [:voc_index, :nox_index, :co2]

  @type device_id :: String.t()
  @type measurement :: %{
          pm1_0: float | nil,
          pm2_5: float | nil,
          pm4_0: float | nil,
          pm10: float | nil,
          temperature: float | nil,
          humidity: float | nil,
          voc_index: integer | nil,
          nox_index: integer | nil,
          co2: integer | nil,
          device_status: non_neg_integer
        }
  @type t ::
          {:hello, device_id, %{product: String.t(), sensor_fw: String.t(), firmware: String.t()}}
          | {:measurement, device_id, measurement}
          | {:device_error, device_id | nil, String.t()}
  @type reason ::
          :invalid_json | :not_an_object | {:unknown_type, term} | {:invalid, atom}

  @spec parse(binary) :: {:ok, t} | {:error, reason}
  def parse(line) do
    case JSON.decode(String.trim_trailing(line, "\r")) do
      {:ok, %{} = object} -> message(object["type"], object)
      {:ok, _other} -> {:error, :not_an_object}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp message("hello", object) do
    with {:ok, device_id} <- device_id(object),
         {:ok, product} <- text(object, :product),
         {:ok, sensor_fw} <- text(object, :sensor_fw),
         {:ok, firmware} <- text(object, :firmware) do
      {:ok, {:hello, device_id, %{product: product, sensor_fw: sensor_fw, firmware: firmware}}}
    end
  end

  defp message("measurement", object) do
    with {:ok, device_id} <- device_id(object),
         {:ok, values} <- fields(object, @decimals, &decimal/1),
         {:ok, indices} <- fields(object, @indices, &index/1),
         {:ok, status} <- device_status(object) do
      {:ok,
       {:measurement, device_id, values |> Map.merge(indices) |> Map.put(:device_status, status)}}
    end
  end

  defp message("error", object) do
    with {:ok, device_id} <- nullable_device_id(object),
         {:ok, message} <- text(object, :message) do
      {:ok, {:device_error, device_id, message}}
    end
  end

  defp message(type, _object), do: {:error, {:unknown_type, type}}

  defp device_id(%{"device_id" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp device_id(_object), do: {:error, {:invalid, :device_id}}

  defp nullable_device_id(%{"device_id" => nil}), do: {:ok, nil}
  defp nullable_device_id(object), do: device_id(object)

  defp text(object, key) do
    case object[Atom.to_string(key)] do
      value when is_binary(value) -> {:ok, value}
      _other -> {:error, {:invalid, key}}
    end
  end

  defp fields(object, keys, cast) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      with {:ok, value} <- Map.fetch(object, Atom.to_string(key)),
           {:ok, value} <- cast.(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        _invalid -> {:halt, {:error, {:invalid, key}}}
      end
    end)
  end

  defp decimal(nil), do: {:ok, nil}
  defp decimal(value) when is_number(value), do: {:ok, value * 1.0}
  defp decimal(_value), do: :error

  defp index(nil), do: {:ok, nil}
  defp index(value) when is_integer(value), do: {:ok, value}
  defp index(_value), do: :error

  defp device_status(%{"device_status" => status}) when is_integer(status) and status >= 0,
    do: {:ok, status}

  defp device_status(_object), do: {:error, {:invalid, :device_status}}
end
