defmodule Ziwoas.Collector.MqttRouterTest do
  # test/mqtt_router_test.rb
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Collector.MqttRouter

  defmodule FakeHandler do
    @behaviour MqttRouter

    @impl true
    def subscriptions({prefix, _handled}), do: ["#{prefix}/#"]

    @impl true
    def matches?({prefix, _handled}, topic), do: String.starts_with?(topic, prefix <> "/")

    @impl true
    def handle({_prefix, _handled}, "boom/" <> _, _payload), do: raise("bad payload")
    def handle({prefix, handled}, topic, payload), do: {prefix, handled ++ [{topic, payload}]}
  end

  defp router(prefixes), do: %{handlers: Enum.map(prefixes, &{FakeHandler, {&1, []}})}

  test "subscriptions are the union of the handlers' filters" do
    assert MqttRouter.subscriptions(router(["shellies", "govee", "shellies"]).handlers) ==
             ["shellies/#", "govee/#"]
  end

  test "dispatch routes a topic to the matching handler" do
    router = MqttRouter.dispatch(router(["shellies", "govee"]), "govee/lamp/status", "payload")

    assert router.handlers == [
             {FakeHandler, {"shellies", []}},
             {FakeHandler, {"govee", [{"govee/lamp/status", "payload"}]}}
           ]
  end

  test "dispatch warns when no handler matches" do
    router = router(["shellies"])

    log =
      capture_log(fn -> assert MqttRouter.dispatch(router, "unknown/topic", "x") == router end)

    assert log =~ "no handler for unknown/topic"
  end

  # Rails' router reconnected after an escaping error; here the handler keeps its state.
  test "a raising handler is logged and keeps its state" do
    router = router(["boom"])
    log = capture_log(fn -> assert MqttRouter.dispatch(router, "boom/x", "{") == router end)
    assert log =~ "bad payload"
  end

  test "the Tortoise callback joins the topic levels" do
    {:ok, state} = MqttRouter.init(router(["shellies"]).handlers)

    assert {:ok,
            %{handlers: [{FakeHandler, {"shellies", [{"shellies/bkw/status/switch:0", "{}"}]}}]}} =
             MqttRouter.handle_message(["shellies", "bkw", "status", "switch:0"], "{}", state)
  end
end
