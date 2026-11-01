defmodule Ziwoas.Lights.Bridge do
  @moduledoc false

  alias Ziwoas.Lights.Light

  @type verb ::
          {:power, boolean}
          | {:brightness, 1..100}
          | {:color, %{r: 0..255, g: 0..255, b: 0..255}}
          | {:color_temp, pos_integer}
          | {:zone, String.t(), boolean}
          | {:scene, String.t()}

  @callback command(key :: String.t(), verb) :: :ok | {:error, term}
  @callback silent?(key :: String.t()) :: boolean
  @doc "The caller gets `{:lamp_heard, key, telemetry | nil}` whenever the bridge hears the lamp."
  @callback watch(key :: String.t()) :: :ok | {:error, :unavailable}
  @callback unwatch(key :: String.t()) :: :ok

  @bridges %{govee: Ziwoas.Govee.Bridge, hue: Ziwoas.Hue.Bridge}

  @spec command(Light.t(), verb) :: :ok | {:error, term}
  def command(light, verb), do: of(light).command(light.key, verb)

  @spec silent?(Light.t()) :: boolean
  def silent?(light), do: of(light).silent?(light.key)

  @spec watch(Light.t()) :: :ok | {:error, :unavailable}
  def watch(light), do: of(light).watch(light.key)

  @spec unwatch(Light.t()) :: :ok
  def unwatch(light), do: of(light).unwatch(light.key)

  defp of(%Light{vendor: vendor}), do: Map.fetch!(@bridges, vendor)

  @typedoc "A bridge's watchers by lamp key, each with its monitor."
  @type watchers :: %{String.t() => {pid, reference}}

  @doc "Calls a bridge; one that is not running or does not answer in time is unavailable."
  @spec call(GenServer.server(), term, timeout) :: term | {:error, :unavailable}
  def call(server, request, timeout) do
    case GenServer.whereis(server) do
      nil -> {:error, :unavailable}
      pid -> GenServer.call(pid, request, timeout)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec add_watcher(watchers, String.t(), pid) :: watchers
  def add_watcher(watchers, key, watcher),
    do: watchers |> drop_watcher(key) |> Map.put(key, {watcher, Process.monitor(watcher)})

  @spec drop_watcher(watchers, String.t()) :: watchers
  def drop_watcher(watchers, key) do
    case Map.pop(watchers, key) do
      {nil, watchers} ->
        watchers

      {{_watcher, ref}, watchers} ->
        Process.demonitor(ref, [:flush])
        watchers
    end
  end

  @doc "Forgets the watcher whose monitor went down."
  @spec watcher_down(watchers, reference) :: watchers
  def watcher_down(watchers, ref),
    do: Map.reject(watchers, fn {_key, {_watcher, watch}} -> watch == ref end)
end
