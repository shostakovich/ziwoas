defmodule Ziwoas.Govee.States do
  @moduledoc """
  Per lamp the published (desired or confirmed) state and how sure the bridge
  is of it. Pure; the bridge keeps it in its state.

    * a command publishes optimistically and stays `:pending` for the window;
    * while pending, a LAN reading that matches confirms (`:synced`), one that
      deviates counts as "not applied yet" and is ignored;
    * after the window, `on: false` is adopted at once; an `on` reading from the LAN
      that deviates asks for the API (`:reconciling`); API telemetry is the truth.

  Published states are maps with atom keys (`:on`, `:brightness`, `:color`, …);
  a `nil` value clears a field (`color_temp_k: nil` after a colour).
  """
  @compare [:on, :brightness, :color, :color_temp_k]

  defstruct window_s: 5.0, entries: %{}

  @type t :: %__MODULE__{}
  @type result :: %{published: map, changed: boolean, needs_api_clarification: boolean}

  def new(window_s), do: %__MODULE__{window_s: window_s}

  def published(%__MODULE__{entries: entries}, key), do: entries[key] && entries[key].published
  def status(%__MODULE__{entries: entries}, key), do: entries[key] && entries[key].status

  @doc "Records a command at monotonic second `now`; returns `{published, store}`."
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

  @doc "Applies telemetry from `source` (`:lan` or `:api`); returns `{result, store}`."
  @spec apply_telemetry(t, String.t(), map, :lan | :api, number) :: {result, t}
  def apply_telemetry(store, key, telemetry, source, now) do
    entry = entry(store, key)
    before = entry.published

    {entry, needs_api} =
      cond do
        entry.status == :pending and now < entry.pending_until ->
          if matches?(entry.published, telemetry),
            do: {adopt(entry, telemetry), false},
            else: {entry, false}

        telemetry[:on] == false ->
          {adopt(entry, telemetry), false}

        source == :lan and not matches?(entry.published, telemetry) ->
          {%{entry | status: :reconciling}, true}

        true ->
          {adopt(entry, telemetry), false}
      end

    result = %{
      published: entry.published,
      changed: entry.published != before,
      needs_api_clarification: needs_api
    }

    {result, put(store, key, entry)}
  end

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
