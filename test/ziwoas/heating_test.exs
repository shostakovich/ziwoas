defmodule Ziwoas.HeatingTest do
  use Ziwoas.DataCase

  alias Ziwoas.Fritz.Thermostat
  alias Ziwoas.Heating
  alias Ziwoas.Heating.{Decision, Heater, Row, Window}

  @key "119600123456"
  @zone "Europe/Berlin"

  defp thermostat(attrs \\ []),
    do:
      struct!(
        %Thermostat{key: @key, ain: "11960 0123456", name: "Wohnzimmer", present: true},
        attrs
      )

  defp error_messages(changeset),
    do: Enum.map(changeset.errors, fn {field, {message, _}} -> {field, message} end)

  describe "register/1" do
    test "a new thermostat becomes a heater at 21 °C under the box's name" do
      assert %Heater{key: @key, ain: "11960 0123456", name: "Wohnzimmer", heat_c: 21.0} =
               Heating.register(thermostat())
    end

    test "a known one takes the box's name and keeps its settings" do
      thermostat() |> Heating.register() |> Heating.put_heat_c!(19.5)

      assert %Heater{name: "Stube", heat_c: 19.5} = Heating.register(thermostat(name: "Stube"))
      assert length(Heating.heaters()) == 1
    end
  end

  describe "windows" do
    setup do
      Heating.register(thermostat())
      :ok
    end

    test "a window is stored in minutes with its start days" do
      assert {:ok,
              %Window{on_minute: 420, off_minute: 1140, days: [1, 2, 3, 4, 5], enabled: true}} =
               Heating.save_window(@key, %{
                 "on_at_time" => "07:00",
                 "off_at_time" => "19:00",
                 "days" => ["", "5", "1", "2", "3", "4"]
               })
    end

    test "a window is refused with the plugs' messages" do
      assert {:error, changeset} =
               Heating.save_window(@key, %{on_at_time: "07:00", off_at_time: "07:00", days: []})

      assert error_messages(changeset) == [
               days: "mindestens ein Wochentag muss gewählt sein",
               off_at_time: "An- und Aus-Zeit müssen sich unterscheiden"
             ]

      assert Heating.windows(@key) == []
    end

    test "editing a window starts from its times and keeps its id" do
      {:ok, window} =
        Heating.save_window(@key, %{on_at_time: "22:00", off_at_time: "06:00", days: [5]})

      form = Ecto.Changeset.apply_changes(Heating.change_window(window))
      assert {form.on_at_time, form.off_at_time, form.days} == {"22:00", "06:00", [5]}

      {:ok, saved} = Heating.save_window(@key, %{on_at_time: "21:30"}, window)
      assert saved.id == window.id

      assert %Window{on_minute: 1290, off_minute: 360} =
               Heating.window(@key, to_string(window.id))
    end

    test "a window is found only under its own heater" do
      {:ok, window} =
        Heating.save_window(@key, %{on_at_time: "07:00", off_at_time: "08:00", days: [1]})

      assert Heating.window("other", to_string(window.id)) == nil
      assert Heating.window(@key, "x") == nil
      assert Heating.window(@key, %{}) == nil
      assert Heating.window(@key, window.id) == nil
    end

    test "a window can be paused and deleted" do
      {:ok, window} =
        Heating.save_window(@key, %{on_at_time: "07:00", off_at_time: "08:00", days: [1]})

      assert %Window{enabled: false} = Heating.set_window_enabled(window, false)
      assert Heating.delete_window(window) == :ok
      assert Heating.windows(@key) == []
    end
  end

  describe "rows/3" do
    test "a row carries the decision, the windows and the latest reading" do
      Ziwoas.TestClock.freeze("2026-11-05T10:00:00+01:00")
      Heating.register(thermostat())
      Heating.save_window(@key, %{on_at_time: "07:00", off_at_time: "19:00", days: [4]})
      now = Ziwoas.Clock.now()

      assert [%Row{decision: %Decision{state: :heat}, entries: [_], thermostat: nil} = row] =
               Heating.rows(nil, now, @zone)

      assert Row.offline?(row)
      assert Row.set_to_heat?(row)

      [row] = Heating.rows(%{@key => thermostat()}, now, @zone)
      refute Row.offline?(row)
      assert Row.offline?(%{row | thermostat: thermostat(present: false)})
    end

    test "while the box answers only the heaters it lists are shown, the others are kept" do
      Heating.register(thermostat())
      Heating.register(thermostat(key: "2", ain: "2", name: "Bad"))
      now = Ziwoas.Clock.now()

      assert [%Row{heater: %Heater{key: @key}}] =
               Heating.rows(%{@key => thermostat()}, now, @zone)

      assert length(Heating.rows(nil, now, @zone)) == 2
      assert length(Heating.heaters()) == 2
    end

    test "the latest press counts" do
      Heating.register(thermostat())
      at = Ziwoas.Clock.parse!("2026-11-05T20:00:00+01:00")
      heater = Heating.get_heater(@key)
      heater = Heating.put_press!(heater, :heat, DateTime.add(at, -60))
      heater = Heating.put_press!(heater, :frost, at)

      assert Heater.press(heater) == {:frost, at}
      assert [%Row{decision: %Decision{state: :frost}}] = Heating.rows(nil, at, @zone)
    end
  end

  test "the target heats at the Heiztemperatur or switches off" do
    assert Heating.target(%Heater{heat_c: 21.5}, :heat) == {:heat, 21.5}
    assert Heating.target(%Heater{heat_c: 21.5}, :frost) == :off
  end
end
