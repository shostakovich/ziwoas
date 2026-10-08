defmodule Ziwoas.Govee.CommandRouter do
  @moduledoc false
  alias Ziwoas.Govee.Device

  @on_off "devices.capabilities.on_off"
  @toggle "devices.capabilities.toggle"
  @scene "devices.capabilities.dynamic_scene"
  @range "devices.capabilities.range"
  @color_setting "devices.capabilities.color_setting"

  @type route :: {:lan, [tuple]} | {:api, keyword}

  @spec route(Device.t(), Ziwoas.Govee.Bridge.verb()) :: {:ok, route} | {:error, :unknown_scene}
  def route(device, {:power, on}) do
    if lan?(device),
      do: lan(device, {:turn, device.ip, on}),
      else: api(device, @on_off, "powerSwitch", if(on, do: 1, else: 0))
  end

  def route(device, {:brightness, value}) do
    if lan?(device),
      do: lan(device, {:brightness, device.ip, value}),
      else: api(device, @range, "brightness", value)
  end

  def route(device, {:color, %{r: r, g: g, b: b} = rgb}) do
    if lan?(device),
      do: lan(device, {:color, device.ip, rgb}),
      else:
        api(
          device,
          @color_setting,
          "colorRgb",
          Bitwise.bor(Bitwise.bsl(r, 16), Bitwise.bor(Bitwise.bsl(g, 8), b))
        )
  end

  def route(device, {:color_temp, kelvin}) do
    if lan?(device),
      do: lan(device, {:color_temp, device.ip, kelvin}),
      else: api(device, @color_setting, "colorTemperatureK", kelvin)
  end

  def route(device, {:zone, name, on}),
    do: api(device, @toggle, name, if(on, do: 1, else: 0))

  def route(device, {:scene, name}) do
    case device.scene_index[name] do
      nil ->
        {:error, :unknown_scene}

      %{id: id, param_id: param_id} ->
        api(device, @scene, "lightScene", %{"id" => id, "paramId" => param_id})
    end
  end

  @spec changes(Ziwoas.Govee.Bridge.verb(), map | nil) :: map
  def changes({:power, on}, _published), do: %{on: on}
  def changes({:brightness, value}, _published), do: %{on: true, brightness: value}
  def changes({:color, rgb}, _published), do: %{on: true, color: rgb, color_temp_k: nil}

  def changes({:color_temp, kelvin}, _published),
    do: %{on: true, color_temp_k: kelvin, color: nil}

  def changes({:scene, _name}, _published), do: %{on: true}

  def changes({:zone, name, on}, published) do
    bits = (published || %{})[:zone_states] || %{}
    changes = %{zone_states: Map.put(bits, name, on)}
    if name == "powerSwitch", do: Map.put(changes, :on, on), else: changes
  end

  defp lan?(%Device{ip: ip, power_only: power_only}), do: not is_nil(ip) and not power_only

  defp lan(device, command), do: {:ok, {:lan, [command, {:request_status, device.ip}]}}

  defp api(device, type, instance, value),
    do:
      {:ok,
       {:api,
        [sku: device.sku, device: device.api_id, type: type, instance: instance, value: value]}}
end
