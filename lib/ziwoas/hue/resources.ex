defmodule Ziwoas.Hue.Resources do
  @moduledoc "The bridge's lights, devices and Zigbee connections by ID, kept current by events."
  alias Ziwoas.Hue.Light

  @kinds ["light", "device", "zigbee_connectivity"]

  @type t :: %{String.t() => map}

  @spec index([map]) :: t
  def index(resources),
    do:
      for(
        %{"id" => id, "type" => type} = r <- resources,
        is_binary(id) and type in @kinds,
        into: %{},
        do: {id, r}
      )

  @spec kept?(map) :: boolean
  def kept?(%{"type" => type}), do: type in @kinds
  def kept?(_resource), do: false

  @spec light_ids(t) :: [String.t()]
  def light_ids(resources), do: for({id, %{"type" => "light"}} <- resources, do: id)

  @spec lamps(t) :: [map]
  def lamps(resources), do: for(id <- light_ids(resources), do: lamp(resources, id))

  @doc "A light source of a device with several takes the device's name before its own."
  @spec lamp(t, String.t()) :: map
  def lamp(resources, id) do
    light = resources[id]
    device = device_of(resources, light)

    own =
      case light do
        %{"metadata" => %{"name" => own}} -> own
        _light -> nil
      end

    name =
      case {device, lights_of(resources, device)} do
        {%{"metadata" => %{"name" => device_name}}, [_, _ | _]} -> "#{device_name} #{own}"
        _single -> own
      end

    Light.lamp(light, name)
  end

  @spec state(t, String.t()) :: map
  def state(resources, id), do: Light.state(resources[id], reachable?(resources, id))

  @spec reachable?(t, String.t()) :: boolean
  def reachable?(resources, id), do: connected?(resources, device_of(resources, resources[id]))

  @doc "Merges partial resources in; answers the lights whose state they may have changed."
  @spec update(t, [map]) :: {t, [String.t()]}
  def update(resources, changes) do
    Enum.reduce(changes, {resources, []}, fn
      %{"id" => id} = change, {resources, touched} when is_map_key(resources, id) ->
        resources = Map.put(resources, id, deep_merge(resources[id], change))
        {resources, touched ++ affected(resources, resources[id])}

      _unknown, acc ->
        acc
    end)
    |> then(fn {resources, touched} -> {resources, Enum.uniq(touched)} end)
  end

  defp affected(_resources, %{"type" => "light", "id" => id}), do: [id]

  defp affected(resources, %{"owner" => %{"rid" => device_id}}),
    do: lights_of(resources, resources[device_id])

  defp affected(resources, %{"type" => "device"} = device), do: lights_of(resources, device)
  defp affected(_resources, _resource), do: []

  defp device_of(resources, %{"owner" => %{"rid" => device_id}}), do: resources[device_id]
  defp device_of(_resources, _light), do: nil

  defp lights_of(_resources, nil), do: []

  defp lights_of(resources, %{"services" => services}) when is_list(services),
    do: for(%{"rid" => id, "rtype" => "light"} <- services, Map.has_key?(resources, id), do: id)

  defp lights_of(_resources, _device), do: []

  defp connected?(_resources, nil), do: true

  defp connected?(resources, %{"id" => device_id}) do
    connections =
      for {_id, %{"type" => "zigbee_connectivity", "owner" => %{"rid" => ^device_id}} = c} <-
            resources,
          do: c["status"]

    connections == [] or "connected" in connections
  end

  defp deep_merge(%{} = known, %{} = change),
    do: Map.merge(known, change, fn _key, old, new -> deep_merge(old, new) end)

  defp deep_merge(_known, change), do: change
end
