defmodule Ziwoas.Govee.States do
  @moduledoc "What a lamp heard on the LAN reports wins; the cloud fills in what the LAN cannot see."
  @compare [:on, :brightness, :color, :color_temp_k]
  @lan_blind [:zone_states]

  defstruct window_s: 5.0, entries: %{}

  @type t :: %__MODULE__{}
  @type result :: %{published: map, changed: boolean}

  def new(window_s), do: %__MODULE__{window_s: window_s}

  def published(%__MODULE__{entries: entries}, key), do: entries[key] && entries[key].published
  def status(%__MODULE__{entries: entries}, key), do: entries[key] && entries[key].status

  @spec record_command(t, String.t(), map, number) :: {map, t}
  def record_command(store, key, changes, now) do
    entry = entry(store, key)

    entry = %{
      entry
      | published: Map.merge(entry.published, changes),
        status: :pending,
        pending_until: now + store.window_s
    }

    {entry.published, put(store, key, entry)}
  end

  @spec apply_lan(t, String.t(), map, number) :: {result, t}
  def apply_lan(store, key, telemetry, now), do: apply_reading(store, key, telemetry, now)

  @spec apply_api(t, String.t(), map, :heard | :not_heard, number) :: {result, t}
  def apply_api(store, key, telemetry, :not_heard, now),
    do: apply_reading(store, key, telemetry, now)

  def apply_api(store, key, telemetry, :heard, now) do
    update(store, key, fn entry ->
      if pending?(entry, now),
        do: entry,
        else: %{entry | published: Map.merge(entry.published, Map.take(telemetry, @lan_blind))}
    end)
  end

  defp apply_reading(store, key, telemetry, now) do
    update(store, key, fn entry ->
      if pending?(entry, now) and not matches?(entry.published, telemetry),
        do: entry,
        else: adopt(entry, telemetry)
    end)
  end

  defp update(store, key, fun) do
    before = entry(store, key)
    entry = fun.(before)

    {%{published: entry.published, changed: entry.published != before.published},
     put(store, key, entry)}
  end

  defp pending?(entry, now), do: entry.status == :pending and now < entry.pending_until

  defp adopt(entry, telemetry),
    do: %{entry | published: Map.merge(entry.published, telemetry), status: :synced}

  # Only the fields the reading has count; an absent field is no deviation.
  defp matches?(published, telemetry),
    do:
      Enum.all?(@compare, fn field ->
        not Map.has_key?(telemetry, field) or published[field] == telemetry[field]
      end)

  defp entry(store, key),
    do: store.entries[key] || %{published: %{}, status: :synced, pending_until: 0.0}

  defp put(store, key, entry), do: %{store | entries: Map.put(store.entries, key, entry)}
end
