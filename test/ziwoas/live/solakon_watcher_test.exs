defmodule Ziwoas.Live.SolakonWatcherTest do
  # The bridge in place of Solakon::MonitorJob's broadcast_dashboard_refresh:
  # a new inverter reading is a live beat on the `solakon` topic.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.Live.SolakonWatcher
  alias Ziwoas.Repo
  alias Ziwoas.Solakon.Reading

  defp reading! do
    Repo.insert!(%Reading{
      taken_at: DateTime.utc_now(),
      active_power_w: 1.0,
      pv_power_w: 1.0,
      battery_power_w: 0.0,
      battery_soc_pct: 50
    })
  end

  defp start_watcher!(repo),
    do:
      start_supervised!({SolakonWatcher, name: nil, interval_ms: 10, repo: repo}, id: make_ref())

  setup do
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
    :ok
  end

  test "a new reading is a live beat with its id", %{repo: repo} do
    reading!()
    start_watcher!(repo)
    refute_receive {:solakon_reading, _}, 50

    %Reading{id: id} = reading!()

    assert_receive {:solakon_reading, ^id}, 500
    refute_receive {:solakon_reading, _}, 50
  end

  test "the first reading in an empty table counts as new", %{repo: repo} do
    start_watcher!(repo)
    %Reading{id: id} = reading!()

    assert_receive {:solakon_reading, ^id}, 500
  end
end
