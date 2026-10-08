defmodule Ziwoas.Trmnl.SensorPushJobTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Repo, TestClock, TestConfigs}
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Trmnl.{Push, SensorPushJob}

  test "pushes the room air of a SEN66 without any SwitchBot" do
    TestClock.freeze("2026-10-08T12:00:00Z")

    config =
      TestConfigs.plugs("""
      sensors:
        - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
      trmnl:
        sensors_webhook_url: https://example.test/sensors
      """)

    Repo.insert!(%Reading{device_id: "SEN", taken_at: DateTime.add(Clock.now(), -30), co2: 700})

    test = self()

    Req.Test.stub(Push, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:pushed, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert SensorPushJob.perform(config: config) == {:ok, :sent}
    assert_received {:pushed, "/sensors", body}

    assert %{"merge_variables" => %{"room" => "Wohnzimmer", "values" => %{"co2" => 700}}} =
             JSON.decode!(body)
  end
end
