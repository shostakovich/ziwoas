defmodule Ziwoas.Scheduler.JobsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Scheduler, TestConfigs}
  alias Ziwoas.Scheduler.{Runner, Schedule}

  defp names(config), do: config |> Scheduler.jobs() |> Enum.map(&elem(&1, 0))

  test "every schedule is valid, every job implements the behaviour and gets the config" do
    config = TestConfigs.load(:inverter)

    for {_name, schedule, {module, opts}} <- Scheduler.jobs(config) do
      assert Schedule.valid?(schedule)
      assert Ziwoas.Scheduler.Job in Keyword.get(module.module_info(:attributes), :behaviour, [])
      assert opts[:config] == config
    end
  end

  test "the full config enables every job" do
    assert names(TestConfigs.load(:inverter)) == [
             :aggregate_energy_samples,
             :fetch_current_weather,
             :fetch_today_weather,
             :fetch_weather_forecast,
             :fetch_historic_weather,
             :poll_sensors,
             :push_trmnl_widget,
             :schedule_tick,
             :solakon_monitor,
             :solakon_snapshot
           ]
  end

  test "a bare config runs only the nightly aggregation" do
    assert names(TestConfigs.plugs()) == [:aggregate_energy_samples]
  end

  test "each job needs its part of the config" do
    assert :fetch_current_weather in names(TestConfigs.located())

    config = TestConfigs.plugs()
    switchable = Enum.map(config.plugs, &%{&1 | switchable: &1.id == "fridge"})
    assert :schedule_tick in names(%{config | plugs: switchable})

    assert :poll_sensors in names(
             TestConfigs.plugs("""
             switchbot: { token: t, secret: s }
             sensors:
               - { id: A, name: A, type: meter_pro_co2 }
             """)
           )

    refute :poll_sensors in names(
             TestConfigs.plugs("sensors:\n  - { id: A, name: A, type: meter_pro_co2 }\n")
           )

    assert :push_trmnl_widget in names(
             TestConfigs.plugs("trmnl:\n  energy_webhook_url: https://e\n")
           )

    refute :push_trmnl_widget in names(
             TestConfigs.plugs("trmnl:\n  sensors_webhook_url: https://s\n")
           )

    assert :solakon_snapshot in names(TestConfigs.plugs("solakon:\n  host: h\n"))

    refute :solakon_monitor in names(
             TestConfigs.plugs("solakon:\n  host: h\n  monitoring_enabled: false\n")
           )
  end

  test "the aggregation backs up into the configured directory" do
    [{:aggregate_energy_samples, {:daily, ~T[03:15:00]}, {_module, opts}}] =
      Scheduler.jobs(TestConfigs.plugs())

    assert opts[:backup_dir] == Application.get_env(:ziwoas, :backup_dir)
  end

  test "children are one runner per job in the location's zone" do
    config = TestConfigs.load(:test)

    assert [{Runner, opts} | _] = children = Scheduler.children(config, clock: :clock)
    assert length(children) == length(Scheduler.jobs(config))
    assert opts[:id] == :aggregate_energy_samples
    assert opts[:zone] == "Europe/Berlin"
    assert opts[:clock] == :clock
  end
end
