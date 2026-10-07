defmodule Ziwoas.Collector.MqttRouter do
  @moduledoc false
  use Tortoise311.Handler

  require Logger

  @callback subscriptions(state :: term) :: [String.t()]
  @callback matches?(state :: term, topic :: String.t()) :: boolean
  @callback handle(state :: term, topic :: String.t(), payload :: binary) :: term

  @type t :: %{handlers: [{module, term}]}

  @spec subscriptions([{module, term}]) :: [String.t()]
  def subscriptions(handlers),
    do:
      handlers
      |> Enum.flat_map(fn {module, state} -> module.subscriptions(state) end)
      |> Enum.uniq()

  @impl Tortoise311.Handler
  def init(handlers), do: {:ok, %{handlers: handlers}}

  @impl Tortoise311.Handler
  def connection(:up, state) do
    Logger.info(
      "MqttRouter: connected, subscribed #{Enum.join(subscriptions(state.handlers), ", ")}"
    )

    {:ok, state}
  end

  def connection(status, state) do
    Logger.warning("MqttRouter: connection #{status}")
    {:ok, state}
  end

  @impl Tortoise311.Handler
  def handle_message(levels, payload, state),
    do: {:ok, dispatch(state, Enum.join(levels, "/"), payload)}

  @spec dispatch(t, String.t(), binary) :: t
  def dispatch(%{handlers: handlers} = state, topic, payload) do
    case Enum.find_index(handlers, fn {module, handler} -> module.matches?(handler, topic) end) do
      nil ->
        Logger.warning("MqttRouter: no handler for #{topic}")
        state

      index ->
        {module, handler} = Enum.at(handlers, index)

        %{
          state
          | handlers:
              List.replace_at(handlers, index, {module, run(module, handler, topic, payload)})
        }
    end
  end

  defp run(module, handler, topic, payload) do
    module.handle(handler, topic, payload)
  rescue
    error ->
      Logger.error(
        "MqttRouter: #{inspect(module)} failed on #{topic}: #{Exception.message(error)}"
      )

      handler
  end
end
