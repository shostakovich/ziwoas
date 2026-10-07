defmodule Ziwoas.ConfigTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Config
  alias Ziwoas.Config.Error

  @valid """
  location:
    timezone: Europe/Berlin
  mqtt:
    host: 192.168.1.103
    port: 1883
    topic_prefix: shellies
  plugs:
    - id: bkw
      name: Balkonkraftwerk
      role: producer
    - id: fridge
      name: Kühlschrank
      role: consumer
  """

  @fritz """
  fritz_box:
    host: 192.168.178.1
    user: fritz6584
    password: secret
  fritz_poll:
    active_interval_seconds: 5
    idle_interval_seconds: 60
    idle_threshold_w: 10
    timeout_seconds: 2
  """

  defp load(yaml), do: Config.from_yaml!(yaml)

  defp error(yaml) do
    %Error{message: message} = assert_raise(Error, fn -> load(yaml) end)
    message
  end

  defp with_coordinates(pairs) do
    extra = Enum.map_join(pairs, fn {key, value} -> "  #{key}: #{value}\n" end)

    String.replace(
      @valid,
      "location:\n  timezone: Europe/Berlin\n",
      "location:\n  timezone: Europe/Berlin\n" <> extra
    )
  end

  test "loads a valid config" do
    cfg = load(@valid)
    assert cfg.location.timezone == "Europe/Berlin"
    assert [%{id: "bkw", role: :producer}, %{id: "fridge", name: "Kühlschrank"}] = cfg.plugs
  end

  test "ignores the legacy aggregator block" do
    cfg = load(@valid <> "aggregator:\n  run_at: \"03:15\"\n  raw_retention_days: 99\n")
    refute Map.has_key?(cfg, :aggregator)
  end

  test "loads mqtt" do
    assert %{host: "192.168.1.103", port: 1883, topic_prefix: "shellies"} = load(@valid).mqtt
  end

  test "loads fritz_poll" do
    assert %{
             active_interval_seconds: 5,
             idle_interval_seconds: 60,
             idle_threshold_w: 10.0,
             timeout_seconds: 2
           } =
             load(@valid <> @fritz).fritz_poll
  end

  test "a shelly plug has no ain and the shelly driver" do
    assert %{driver: :shelly, ain: nil} = hd(load(@valid).plugs)
  end

  test "fritz_poll is required with a fritz_dect plug" do
    yaml =
      @valid <>
        """
        fritz_box:
          host: 192.168.178.1
          user: fritz6584
          password: secret
        """

    yaml =
      String.replace(
        yaml,
        "role: consumer",
        "role: consumer\n    driver: fritz_dect\n    ain: \"08761 0500475\""
      )

    assert error(yaml) =~ ~r/fritz_poll/i
  end

  test "mqtt is required" do
    yaml = String.replace(@valid, ~r/mqtt:.*topic_prefix: shellies\n/s, "")
    assert error(yaml) =~ ~r/mqtt/i
  end

  test "rejects duplicate plug ids" do
    assert error(String.replace(@valid, "id: fridge", "id: bkw")) =~ ~r/duplicate plug id/i
  end

  test "rejects a config without a producer" do
    assert error(String.replace(@valid, "role: producer", "role: consumer")) =~
             ~r/at least one.*producer/i
  end

  test "rejects an invalid time zone by name" do
    message = error(String.replace(@valid, "Europe/Berlin", "Not/ATimezone"))
    assert message =~ "location.timezone"
    assert message =~ "Not/ATimezone"
  end

  test "requires a location" do
    assert error(String.replace(@valid, "location:\n  timezone: Europe/Berlin\n", "")) =~
             ~r/location/i
  end

  test "rejects a location without a timezone, or an empty one" do
    no_key =
      String.replace(
        @valid,
        "location:\n  timezone: Europe/Berlin\n",
        "location:\n  lat: 52.52\n  lon: 13.405\n"
      )

    assert error(no_key) =~ "location.timezone"

    assert error(String.replace(@valid, "timezone: Europe/Berlin", "timezone: \"\"")) =~
             "location.timezone"
  end

  test "rejects a fritz_dect plug without ain" do
    yaml =
      String.replace(@valid <> @fritz, "role: consumer", "role: consumer\n    driver: fritz_dect")

    assert error(yaml) =~ ~r/ain.*required/i
  end

  test "loads optional coordinates" do
    location = load(with_coordinates(lat: 52.52, lon: 13.405)).location
    assert location.lat == 52.52
    assert location.lon == 13.405
    assert Ziwoas.Location.located?(location)
  end

  test "coordinates are optional" do
    location = load(@valid).location
    assert is_nil(location.lat) and is_nil(location.lon)
    refute Ziwoas.Location.located?(location)
  end

  test "rejects coordinates off the globe, half a position and non-numbers" do
    assert error(with_coordinates(lat: 100, lon: 13.405)) =~ "location.lat"
    assert error(with_coordinates(lat: 52.52, lon: 200)) =~ "location.lon"
    assert error(with_coordinates(lon: 13.405)) =~ "location.lat"
    assert error(with_coordinates(lat: 52.52)) =~ "location.lon"
    assert error(with_coordinates(lat: 52.52, lon: "east")) =~ "location.lon"
  end

  test "plug room is optional" do
    yaml =
      String.replace(
        @valid,
        "name: Balkonkraftwerk\n    role: producer",
        "name: Balkonkraftwerk\n    role: producer\n    room: Balkon"
      )

    assert [%{room: "Balkon"}, %{room: nil}] = load(yaml).plugs
  end

  test "loads switchbot and sensors" do
    cfg =
      load(
        @valid <>
          """
          switchbot:
            token: "tok-abc"
            secret: "sec-xyz"
          sensors:
            - id: "ABCDEF"
              name: "Wohnzimmer"
              type: meter_pro_co2
              room: "Wohnzimmer"
            - id: "FEDCBA"
              name: "Schlafzimmer"
              type: meter_pro_co2
            - id: "112233"
              name: "Balkon"
              type: outdoor_meter
          """
      )

    assert %{token: "tok-abc", secret: "sec-xyz"} = cfg.switchbot

    assert [
             %{id: "ABCDEF", name: "Wohnzimmer", type: :meter_pro_co2, room: "Wohnzimmer"},
             %{room: nil},
             %{id: "112233", type: :outdoor_meter}
           ] = cfg.sensors
  end

  test "switchbot and sensors are optional" do
    cfg = load(@valid)
    assert cfg.switchbot == nil
    assert cfg.sensors == []
  end

  test "rejects switchbot without token, unknown sensor types and duplicate sensor ids" do
    assert error(@valid <> "switchbot:\n  secret: \"sec-only\"\n") =~ "switchbot.token"

    sensors = "switchbot:\n  token: t\n  secret: s\nsensors:\n"

    assert error(@valid <> sensors <> "  - id: X\n    name: X\n    type: foo_meter\n") =~
             "sensors[0].type"

    duplicate =
      "  - id: DUP\n    name: A\n    type: meter_pro_co2\n  - id: DUP\n    name: B\n    type: meter_pro_co2\n"

    assert error(@valid <> sensors <> duplicate) =~ ~r/duplicate sensor id/i
  end

  test "trmnl urls: both, none, partial; strings only, known keys only" do
    both =
      load(
        @valid <> "trmnl:\n  energy_webhook_url: https://e\n  sensors_webhook_url: https://s\n"
      ).trmnl

    assert %{energy_webhook_url: "https://e", sensors_webhook_url: "https://s"} = both
    assert %{energy_webhook_url: nil, sensors_webhook_url: nil} = load(@valid).trmnl

    assert %{energy_webhook_url: nil, sensors_webhook_url: "https://s"} =
             load(@valid <> "trmnl:\n  sensors_webhook_url: https://s\n").trmnl

    assert_raise Error, fn -> load(@valid <> "trmnl:\n  energy_webhook_url: 42\n") end
    assert error(@valid <> "trmnl:\n  bogus: yes\n") =~ "trmnl"
  end

  test "switchable defaults to false, must be a boolean and never on a producer" do
    assert [%{switchable: false}, %{switchable: false}] = load(@valid).plugs

    switchable = String.replace(@valid, "role: consumer", "role: consumer\n    switchable: true")
    assert [%{switchable: false}, %{switchable: true}] = load(switchable).plugs

    assert error(
             String.replace(
               @valid,
               "role: consumer",
               "role: consumer\n    switchable: yes please"
             )
           ) =~
             "switchable must be true or false"

    assert error(String.replace(@valid, "role: producer", "role: producer\n    switchable: true")) =~
             ~r/producer.*switchable/
  end

  test "YAML 1.1 booleans: an unquoted yes is true" do
    switchable = String.replace(@valid, "role: consumer", "role: consumer\n    switchable: yes")
    assert [_, %{switchable: true}] = load(switchable).plugs
  end

  test "a missing file and broken YAML are config errors" do
    assert {:error, "config file not found: /nonexistent/path/ziwoas.yml"} =
             Config.load("/nonexistent/path/ziwoas.yml")

    assert Config.from_yaml("location: [nope") == {:error, "config file is not valid YAML"}
    assert Config.from_yaml("- a list") == {:error, "config root must be a mapping"}
    assert Config.from_yaml("") == {:error, "config root must be a mapping"}
  end

  test "the fixture loads" do
    assert {:ok, %Config{location: %{timezone: "Europe/Berlin"}}} =
             Config.load(Ziwoas.TestConfigs.file(:test))
  end

  test "one message lists every error, each with its path" do
    yaml = """
    location:
      timezone: Mars/Olympus
    mqtt:
      host: h
      port: zero
    plugs:
      - id: Bad-Id
        role: producer
      - id: fridge
        name: Fridge
        role: freezer
    sensors: nope
    """

    message = error(yaml)

    for part <- [
          "location.timezone 'Mars/Olympus' is not a valid IANA timezone",
          "mqtt.port must be a number",
          "mqtt.topic_prefix is required",
          "plugs[0].id must contain only a-z, 0-9 and _",
          "plugs[0].name is required",
          "plugs[1].role must be one of producer, consumer",
          "sensors must be a list of mappings"
        ] do
      assert message =~ part
    end

    assert length(String.split(message, "; ")) == 7
  end

  @solakon "solakon:\n  host: 192.168.1.50\n"

  test "solakon is nil when absent and parses a full block" do
    assert load(@valid).solakon == nil

    full =
      @solakon <>
        "  port: 502\n  unit_id: 1\n  monitoring_enabled: true\n  control_enabled: false\n"

    assert %{
             host: "192.168.1.50",
             port: 502,
             unit_id: 1,
             monitoring_enabled: true,
             control_enabled: false
           } =
             load(@valid <> full).solakon
  end

  test "solakon's retired enabled key is ignored like any unknown key" do
    assert %{monitoring_enabled: true, control_enabled: false} =
             load(@valid <> @solakon <> "  enabled: false\n").solakon

    refute Map.has_key?(load(@valid <> @solakon <> "  enabled: false\n").solakon, :enabled)
  end

  test "solakon flags must be booleans" do
    assert error(@valid <> @solakon <> "  monitoring_enabled: maybe\n") =~
             "solakon.monitoring_enabled must be true or false"

    assert error(@valid <> @solakon <> "  control_enabled: maybe\n") =~
             "solakon.control_enabled must be true or false"
  end

  test "solakon applies defaults and requires a host" do
    assert %{port: 502, unit_id: 1, monitoring_enabled: true, control_enabled: false} =
             load(@valid <> "solakon:\n  host: 10.0.0.9\n").solakon

    assert_raise Error, fn -> load(@valid <> "solakon:\n  port: 502\n") end
  end

  test "retired top-level keys are ignored silently like any unknown key" do
    for key <- [
          "timezone: Europe/Berlin\n",
          "weather:\n  lat: 52.5\n  lon: 13.4\n",
          "electricity_price_eur_per_kwh: 0.3\n",
          "migration:\n  owners:\n    weather: shadow\n",
          "migration: nonsense\n"
        ] do
      log = capture_log(fn -> assert %Config{} = load(key <> @valid) end)
      assert log == ""
    end

    assert %{lat: nil, lon: nil} = load("weather:\n  lat: 52.5\n  lon: 13.4\n" <> @valid).location
  end

  test "numbers may be quoted, but must be numbers" do
    quoted = String.replace(@valid, "port: 1883", ~s(port: "1883"))
    assert load(quoted).mqtt.port == 1883

    assert error(String.replace(@valid, "port: 1883", "port: abc")) =~
             "mqtt.port must be a number"

    assert error(String.replace(@valid, "port: 1883", "port: 0")) =~ "mqtt.port must be > 0"

    assert error(@valid <> @solakon <> "  port: x\n") =~ "solakon.port must be a number"

    assert error(@valid <> "govee:\n  lan_poll_seconds: soon\n") =~
             "govee.lan_poll_seconds must be a number"
  end

  test "integers read as leniently as ever: 8.0 is 8, a trailing unit is dropped" do
    assert load(@valid <> "govee:\n  lan_poll_seconds: 8.0\n").govee.lan_poll_seconds == 8
    assert load(String.replace(@valid, "port: 1883", ~s(port: "1883 "))).mqtt.port == 1883
    assert load(@valid <> @solakon <> "  unit_id: 0\n").solakon.unit_id == 0
  end

  test "a govee device that is not a mapping is a config error" do
    assert error(@valid <> "govee:\n  devices:\n    - 14ABDB4844064B60\n") =~
             "govee.devices must be a list of mappings"
  end

  test "an idle threshold of zero is allowed, a negative one is not" do
    zero = String.replace(@valid <> @fritz, "idle_threshold_w: 10", "idle_threshold_w: 0")
    assert load(zero).fritz_poll.idle_threshold_w == 0.0

    negative = String.replace(@valid <> @fritz, "idle_threshold_w: 10", "idle_threshold_w: -1")

    assert error(negative) =~
             "fritz_poll.idle_threshold_w must be >= 0"
  end

  @minimal "location: { timezone: Europe/Berlin }\nmqtt: { host: h, port: 1883, topic_prefix: shellies }\nplugs: []\n"

  test "govee parses intervals, the device map and the api key" do
    govee = """
    govee:
      api_key: yml-secret-key
      lan_poll_seconds: 8
      api_poll_seconds: 180
      pending_window_seconds: 5
      devices:
        - { key: 14ABDB4844064B60, name: "Uplighter", room: "Wohnzimmer" }
    """

    cfg = load(@minimal <> govee)
    assert %{api_key: "yml-secret-key", lan_poll_seconds: 8} = cfg.govee
    assert cfg.govee.names["14ABDB4844064B60"] == %{name: "Uplighter"}
    assert load(@minimal).govee == nil

    assert load(@minimal <> "govee:\n  devices: { key: K1, name: Lampe }\n").govee.names == %{
             "K1" => %{name: "Lampe"}
           }
  end
end
