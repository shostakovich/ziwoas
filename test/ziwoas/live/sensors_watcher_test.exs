defmodule Ziwoas.Live.SensorsWatcherTest do
  # The bridge in place of test/sensors_broadcaster_test.rb: what Rails broadcasts
  # after a sensor poll, the watcher broadcasts when a new reading shows up.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.Live.SensorsWatcher
  alias Ziwoas.Repo
  alias Ziwoas.Sensors.Reading

  defp reading!(device_id),
    do:
      Repo.insert!(%Reading{
        device_id: device_id,
        taken_at: DateTime.utc_now(),
        temperature: 21.0
      })

  defp start_watcher!(repo),
    do:
      start_supervised!(
        {SensorsWatcher, name: nil, interval_ms: 10, repo: repo},
        id: make_ref()
      )

  setup do
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "sensors")
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "weather")
    :ok
  end

  test "a new reading refreshes the sensors dashboard and the current weather", %{repo: repo} do
    reading!("TEST_INDOOR")
    start_watcher!(repo)
    refute_receive {:sensors_updated}, 50

    reading!("TEST_INDOOR")

    assert_receive {:sensors_updated}, 500
    assert_receive {:weather_updated}, 500
    refute_receive {:sensors_updated}, 50
  end

  test "the first reading in an empty table counts as new", %{repo: repo} do
    start_watcher!(repo)
    reading!("TEST_OUTDOOR")

    assert_receive {:sensors_updated}, 500
  end
end
