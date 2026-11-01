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

  @bridges %{govee: Ziwoas.Govee.Bridge}

  @spec command(Light.t(), verb) :: :ok | {:error, term}
  def command(light, verb), do: of(light).command(light.key, verb)

  @spec silent?(Light.t()) :: boolean
  def silent?(light), do: of(light).silent?(light.key)

  @spec watch(Light.t()) :: :ok | {:error, :unavailable}
  def watch(light), do: of(light).watch(light.key)

  @spec unwatch(Light.t()) :: :ok
  def unwatch(light), do: of(light).unwatch(light.key)

  defp of(%Light{vendor: vendor}), do: Map.fetch!(@bridges, vendor)
end
