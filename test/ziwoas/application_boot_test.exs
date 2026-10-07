defmodule Ziwoas.ApplicationBootTest do
  use ExUnit.Case, async: false

  alias Ziwoas.{Config, TestConfigs}

  @devices [collector: true, scheduler: true]

  test "the app booted with the configured file" do
    assert Config.fetch() == Config.load(Config.path())
    assert %Config{} = Config.get()
  end

  test "a valid config starts the collector and the scheduler with it, the endpoint last" do
    config = TestConfigs.load(:test)

    assert Ziwoas.Application.children({:ok, config}, @devices) == [
             Ziwoas.Repo,
             {Phoenix.PubSub, name: Ziwoas.PubSub},
             {Ziwoas.Collector, config: config},
             {Ziwoas.Scheduler, config: config},
             ZiwoasWeb.Endpoint
           ]
  end

  test "a config that fails to load still serves pages, but starts no device and no job" do
    assert Ziwoas.Application.children({:error, "mqtt is required"}, @devices) == [
             Ziwoas.Repo,
             {Phoenix.PubSub, name: Ziwoas.PubSub},
             ZiwoasWeb.Endpoint
           ]
  end

  test "tests start neither collector nor scheduler" do
    children =
      Ziwoas.Application.children({:ok, TestConfigs.load(:test)},
        collector: false,
        scheduler: false
      )

    assert length(children) == 3
  end

  test "fetch answers the load error, get raises it" do
    TestConfigs.put({:error, "mqtt is required"})

    assert Config.fetch() == {:error, "mqtt is required"}
    assert_raise Config.Error, "mqtt is required", &Config.get/0
  end

  test "a config put for a test is the one get answers" do
    config = TestConfigs.load(:inverter)
    TestConfigs.put(config)

    assert Config.get() == config
    assert Config.fetch() == {:ok, config}
  end
end
