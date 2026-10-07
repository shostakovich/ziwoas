defmodule Ziwoas.Lights.GoveeSubscriber do
  @moduledoc """
  Rails' `Govees::Subscriber` (task `light_ingest`), a `Ziwoas.Collector.MqttRouter`
  handler: `govees/<key>/config` upserts a `lights` row, `govees/<key>/state`
  records `light_states` (native units; absent fields stay untouched). Writes go
  through `Ziwoas.Repo.write/2`.

  Rails also re-renders the light card and the detail hero over Turbo after every
  state message; here `{:light_updated, key}` goes out on `light_<key>` (`LightLive`)
  and `lights` (`SwitchesLive`), only as owner (`Ziwoas.Live.broadcast/3`). Rails'
  pages stop hearing from the ingest once Phoenix owns it (see the README).

  Rails' serialized columns store an empty list or map as NULL; so does this.
  """
  @behaviour Ziwoas.Collector.MqttRouter

  require Logger

  alias Ziwoas.{Clock, Live, Repo}
  alias Ziwoas.Govee.Messages
  alias Ziwoas.Lights.{Light, State}

  defstruct task: :light_ingest

  @type t :: %__MODULE__{task: atom}

  @key_format ~r/\A[0-9A-Za-z]+\z/

  def new(opts \\ []), do: %__MODULE__{task: Keyword.get(opts, :task, :light_ingest)}

  @impl Ziwoas.Collector.MqttRouter
  def subscriptions(_state), do: ["govees/+/config", "govees/+/state"]

  @impl Ziwoas.Collector.MqttRouter
  def matches?(_state, topic),
    do:
      String.starts_with?(topic, "govees/") and
        (String.ends_with?(topic, "/config") or String.ends_with?(topic, "/state"))

  @impl Ziwoas.Collector.MqttRouter
  def handle(state, topic, payload) do
    key = Enum.at(String.split(topic, "/"), 1)

    cond do
      String.ends_with?(topic, "/config") -> handle_config(state, key, topic, payload)
      String.ends_with?(topic, "/state") -> handle_state(state, key, topic, payload)
    end

    state
  end

  defp handle_config(state, key, topic, payload) do
    with {:ok, %{} = hash} <- JSON.decode(payload),
         {:ok, config} <- Messages.config(hash),
         :ok <- Repo.write(state.task, fn -> upsert_light(key, config) end) do
      :ok
    else
      _ -> Logger.warning("Govee subscriber: invalid config on #{topic}")
    end
  end

  defp upsert_light(key, config) do
    {light, name} =
      case Repo.get_by(Light, key: key) do
        nil -> {%Light{key: key}, present(config.name) || key}
        light -> {light, light.name}
      end

    changes =
      %{
        name: name,
        supports_color: config.supports_color,
        supports_color_temp: config.supports_color_temp,
        zones: blank_to_nil(config.zones),
        firmware_scenes: blank_to_nil(config.scenes)
      }
      |> put_unless(:sku, present(config.sku))
      |> put_unless(:color_temp_min_k, config.color_temp_min_k)
      |> put_unless(:color_temp_max_k, config.color_temp_max_k)

    if valid_light?(key, name) do
      light |> Ecto.Changeset.change(changes) |> Repo.insert_or_update!()
      :ok
    else
      :invalid
    end
  end

  defp valid_light?(key, name), do: present(name) != nil and Regex.match?(@key_format, key || "")

  defp handle_state(state, key, topic, payload) do
    with {:ok, %{} = hash} <- JSON.decode(payload),
         {:ok, message} <- Messages.state(hash),
         :ok <- Repo.write(state.task, fn -> record_state(key, message) end) do
      broadcast(state.task, key)
      :ok
    else
      _ -> Logger.warning("Govee subscriber: invalid state on #{topic}")
    end
  end

  defp broadcast(task, key) do
    Live.broadcast(task, "light_#{key}", {:light_updated, key})
    Live.broadcast(task, "lights", {:light_updated, key})
  end

  # LightState.record_state + record_zone_state, merged into one write.
  defp record_state(key, message) when key not in [nil, ""] do
    row = Repo.get_by(State, light_key: key) || %State{light_key: key}

    changes =
      %{on: message.on, reachable: message.reachable, last_seen_at: Clock.now()}
      |> put_present(message, :brightness)
      |> put_present(message, :color_temp_k)
      |> put_color(message)
      |> put_zones(row, message)

    row |> Ecto.Changeset.change(changes) |> Repo.insert_or_update!()
    :ok
  end

  defp record_state(_key, _message), do: :invalid

  defp put_color(changes, %{color: %{r: r, g: g, b: b}}),
    do: Map.merge(changes, %{color_r: r, color_g: g, color_b: b})

  defp put_color(changes, _message), do: changes

  defp put_zones(changes, row, %{zone_states: zones}) when zones != %{},
    do: Map.put(changes, :zone_states, Map.merge(row.zone_states || %{}, zones))

  defp put_zones(changes, _row, _message), do: changes

  defp put_present(changes, message, key),
    do: if(Map.has_key?(message, key), do: Map.put(changes, key, message[key]), else: changes)

  defp put_unless(changes, _key, nil), do: changes
  defp put_unless(changes, key, value), do: Map.put(changes, key, value)

  defp blank_to_nil([]), do: nil
  defp blank_to_nil(list), do: list

  defp present(nil), do: nil
  defp present(text), do: if(String.trim(text) == "", do: nil, else: text)
end
