defmodule Ziwoas.Govee.CommandRouter do
  @moduledoc """
  Rails' `Govees::CommandRouter`: one `govees/<key>/set` verb becomes a LAN or a
  Platform API call and an optimistic store entry. Power, brightness, colour and
  colour temperature prefer the LAN when the lamp's IP is known (and it is not a
  power-only lamp); zones and scenes are API-only.

  `io` carries the two effects: `lan: fn command -> … end` (a `Ziwoas.Govee.Lan`
  command tuple) and `api: fn control_keyword -> … end`. Either may raise; the
  bridge logs it, as Rails' does.
  """
  require Logger

  alias Ziwoas.Govee.{Device, Messages, StateStore}

  @on_off "devices.capabilities.on_off"
  @toggle "devices.capabilities.toggle"
  @scene "devices.capabilities.dynamic_scene"
  @range "devices.capabilities.range"
  @color_setting "devices.capabilities.color_setting"

  @doc """
  Handles `verb` (a decoded JSON map) for `device` (nil when unknown) at monotonic
  second `now`; returns `{published | nil, store}` or `{:error, :invalid}` when the
  verb does not coerce.
  """
  @spec handle(Device.t() | nil, String.t(), map, StateStore.t(), map, number) ::
          {map | nil, StateStore.t()} | {:error, :invalid}
  def handle(nil, key, _verb, store, _io, _now) do
    Logger.warning("Govee.CommandRouter: unknown device #{key}")
    {nil, store}
  end

  def handle(%Device{} = device, key, verb, store, io, now) do
    case Messages.set(verb) do
      :error ->
        {:error, :invalid}

      {:ok, nil} ->
        Logger.warning("Govee.CommandRouter: unknown verb #{inspect(Map.keys(verb))}")
        {nil, store}

      {:ok, command} ->
        case changes(device, command, store, io) do
          changes when changes == %{} -> {nil, store}
          changes -> StateStore.record_command(store, key, changes, now)
        end
    end
  end

  defp lan?(%Device{ip: ip, power_only: power_only}), do: not is_nil(ip) and not power_only

  defp changes(device, {:power, on}, _store, io) do
    if lan?(device) do
      io.lan.({:turn, device.ip, on})
      io.lan.({:request_status, device.ip})
    else
      control(device, io, @on_off, "powerSwitch", if(on, do: 1, else: 0))
    end

    %{on: on}
  end

  defp changes(device, {:brightness, value}, _store, io) do
    if lan?(device) do
      io.lan.({:brightness, device.ip, value})
      io.lan.({:request_status, device.ip})
    else
      control(device, io, @range, "brightness", value)
    end

    %{on: true, brightness: value}
  end

  defp changes(device, {:color, %{r: r, g: g, b: b} = rgb}, _store, io) do
    if lan?(device) do
      io.lan.({:color, device.ip, rgb})
      io.lan.({:request_status, device.ip})
    else
      control(
        device,
        io,
        @color_setting,
        "colorRgb",
        Bitwise.bor(Bitwise.bsl(r, 16), Bitwise.bor(Bitwise.bsl(g, 8), b))
      )
    end

    %{on: true, color: rgb, color_temp_k: nil}
  end

  defp changes(device, {:color_temp, kelvin}, _store, io) do
    if lan?(device) do
      io.lan.({:color_temp, device.ip, kelvin})
      io.lan.({:request_status, device.ip})
    else
      control(device, io, @color_setting, "colorTemperatureK", kelvin)
    end

    %{on: true, color_temp_k: kelvin, color: nil}
  end

  defp changes(device, {:zone, name, on}, store, io) do
    control(device, io, @toggle, name, if(on, do: 1, else: 0))
    bits = (StateStore.published(store, device.key) || %{})[:zone_states] || %{}
    changes = %{zone_states: Map.put(bits, name, on)}
    # powerSwitch is the power capability: keep the canonical `on` in step.
    if name == "powerSwitch", do: Map.put(changes, :on, on), else: changes
  end

  defp changes(device, {:scene, name}, _store, io) do
    case device.scene_index[name] do
      nil ->
        Logger.warning("Govee.CommandRouter: unknown scene '#{name}' for #{device.key}")
        %{}

      %{id: id, param_id: param_id} ->
        control(device, io, @scene, "lightScene", [{"id", id}, {"paramId", param_id}])
        %{on: true}
    end
  end

  defp control(device, io, type, instance, value),
    do:
      io.api.(
        sku: device.sku,
        device: device.api_id,
        type: type,
        instance: instance,
        value: value
      )
end
