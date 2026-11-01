defmodule Ziwoas.HueFixtures do
  @moduledoc false

  @resources Path.expand("../fixtures/hue_resources.json", __DIR__)
  @external_resource @resources

  @twilight_back "00000004-0000-4000-8000-000000000004"
  @twilight_front "00000005-0000-4000-8000-000000000005"
  @twilight_connectivity "00000003-0000-4000-8000-000000000003"
  @candle "0000000a-0000-4000-8000-00000000000a"
  @candle_connectivity "00000009-0000-4000-8000-000000000009"
  @colour_only "0000000d-0000-4000-8000-00000000000d"

  def twilight_back, do: @twilight_back
  def twilight_front, do: @twilight_front
  def twilight_connectivity, do: @twilight_connectivity
  def candle, do: @candle
  def candle_connectivity, do: @candle_connectivity
  def colour_only, do: @colour_only

  def key(id), do: String.replace(id, "-", "")

  def bridge_id, do: "001788FFFE6A1B2C"

  def resources, do: @resources |> File.read!() |> JSON.decode!() |> Map.fetch!("data")

  def resource(id), do: Enum.find(resources(), &(&1["id"] == id))

  @doc "The resource list with one light's fields replaced."
  def resources_with(id, fields) do
    Enum.map(resources(), fn
      %{"id" => ^id} = light -> Map.merge(light, fields)
      resource -> resource
    end)
  end

  def resource_body(resources \\ resources()),
    do: JSON.encode!(%{"errors" => [], "data" => resources})

  @doc "Server-sent events as the bridge sends them: a greeting, then one event per block."
  def event_stream(events) do
    blocks =
      for {event, index} <- Enum.with_index(events),
          do: "id: 1700000000:#{index}\ndata: #{JSON.encode!([event])}\n\n"

    Enum.join([": hi\n\n" | blocks])
  end

  def connectivity(id, status),
    do: update([%{"id" => id, "type" => "zigbee_connectivity", "status" => status}])

  def update(changes),
    do: %{
      "creationtime" => "2026-11-01T09:00:00Z",
      "id" => "e0000000-0000-4000-8000-000000000001",
      "type" => "update",
      "data" => changes
    }
end
