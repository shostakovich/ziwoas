defmodule Ziwoas.Plugs.ShellyStatusHandler do
  @moduledoc false
  @behaviour Ziwoas.Collector.MqttRouter

  require Logger

  alias Ziwoas.Config
  alias Ziwoas.Plugs.{Ingest, Roster}

  defstruct [:prefix, :roster, :ingest]

  @type t :: %__MODULE__{}

  @spec new(Config.t(), keyword) :: t
  def new(%Config{} = config, opts \\ []) do
    %__MODULE__{
      prefix: config.mqtt.topic_prefix,
      roster: Config.plug_roster(config),
      ingest: Ingest.new(opts)
    }
  end

  @impl Ziwoas.Collector.MqttRouter
  def subscriptions(%__MODULE__{prefix: prefix}), do: ["#{prefix}/+/status/switch:0"]

  @impl Ziwoas.Collector.MqttRouter
  def matches?(%__MODULE__{prefix: prefix}, topic), do: String.starts_with?(topic, prefix <> "/")

  @impl Ziwoas.Collector.MqttRouter
  def handle(%__MODULE__{} = state, topic, payload) do
    plug_id = Enum.at(String.split(topic, "/"), length(String.split(state.prefix, "/")))

    with {:ok, plug} <- fetch_plug(state, plug_id),
         {:ok, reading} <- parse(payload) do
      %{state | ingest: Ingest.record(state.ingest, plug, reading)}
    else
      {:error, reason} ->
        Logger.warning("ShellyStatusHandler: #{describe(reason)} on #{topic}")
        state
    end
  end

  defp fetch_plug(state, plug_id) do
    case Roster.find(state.roster, plug_id) do
      nil -> {:error, {:unknown_plug, plug_id}}
      plug -> {:ok, plug}
    end
  end

  defp parse(payload) do
    case JSON.decode(payload) do
      {:ok, %{"apower" => apower, "aenergy" => %{"total" => total}} = data}
      when is_number(apower) and is_number(total) ->
        {:ok, %{apower_w: apower * 1.0, aenergy_wh: total * 1.0, output: output(data["output"])}}

      {:ok, data} when is_map(data) ->
        {:error, :incomplete_status}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp output(output) when is_boolean(output), do: output
  defp output(_output), do: nil

  defp describe({:unknown_plug, plug_id}), do: "unknown plug '#{plug_id}'"
  defp describe(:incomplete_status), do: "status without apower or aenergy.total"
  defp describe(:invalid_json), do: "invalid JSON"
end
