defmodule Ziwoas.Heating.DecisionTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Heating.{Decision, Window}

  @zone "Europe/Berlin"
  @weekdays %Window{on_minute: 7 * 60, off_minute: 19 * 60, days: [1, 2, 3, 4, 5], enabled: true}

  # 2026-11-02 is a Monday, 2026-11-05 a Thursday.
  defp at(date, time),
    do: DateTime.new!(Date.from_iso8601!(date), Time.from_iso8601!(time), @zone)

  defp thursday(time), do: at("2026-11-05", time)

  defp press(state, at), do: {state, at}

  defp decide(now, event \\ nil, windows \\ [@weekdays]),
    do: Decision.decide(windows, event, now, @zone)

  defp assert_at(actual, expected),
    do: assert(DateTime.compare(actual, expected) == :eq, "#{actual} is not #{expected}")

  describe "the spec's scenarios" do
    test "manual heating lasts four hours" do
      saturday = &at("2026-11-07", &1)
      event = press(:heat, saturday.("14:00:00"))

      decision = decide(saturday.("14:00:00"), event)
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, saturday.("18:00:00"))

      assert %Decision{state: :frost, cause: :cap} = decide(saturday.("18:00:00"), event)
    end

    test "manual heating inside a window keeps heating until the window ends" do
      assert %Decision{state: :frost} =
               decide(thursday("14:00:00"), press(:frost, thursday("10:00:00")))

      event = press(:heat, thursday("14:00:00"))
      decision = decide(thursday("14:00:00"), event)
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, thursday("19:00:00"))

      assert %Decision{state: :heat, cause: :manual} = decide(thursday("18:30:00"), event)
      assert %Decision{state: :frost, cause: :window} = decide(thursday("19:00:00"), event)
    end

    test "the evening switch-off ends manual heating early" do
      decision = decide(thursday("20:15:00"), press(:heat, thursday("20:15:00")))
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, thursday("22:00:00"))
    end

    test "manual heating after 22:00 still ends after four hours" do
      decision = decide(thursday("23:30:00"), press(:heat, thursday("23:30:00")))
      assert %Decision{state: :heat} = decision
      assert_at(decision.until, at("2026-11-06", "03:30:00"))
    end

    test "a time window takes over manual heating" do
      monday = &at("2026-11-02", &1)
      event = press(:heat, monday.("05:00:00"))

      decision = decide(monday.("05:00:00"), event)
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, monday.("19:00:00"))

      assert %Decision{state: :heat, cause: :window} = decide(monday.("09:30:00"), event)
    end

    test "frost protection inside a window lasts until the next window" do
      assert %Decision{state: :heat, cause: :window} = decide(thursday("09:59:00"))

      decision = decide(thursday("10:00:00"), press(:frost, thursday("10:00:00")))
      assert %Decision{state: :frost, cause: :manual} = decision
      assert_at(decision.until, at("2026-11-06", "07:00:00"))
    end

    test "turning the thermostat by hand counts as manual heating" do
      saturday = &at("2026-11-07", &1)
      noticed = press(:heat, saturday.("14:01:00"))

      decision = decide(saturday.("14:01:00"), noticed)
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, saturday.("18:01:00"))
    end

    test "a window running past 22:00 skips the evening switch-off" do
      saturday = &at("2026-11-07", &1)
      evening = %Window{on_minute: 18 * 60, off_minute: 23 * 60, days: [6], enabled: true}
      windows = [@weekdays, evening]

      decision = decide(saturday.("21:59:00"), nil, windows)
      assert %Decision{state: :heat, cause: :window} = decision
      assert_at(decision.until, saturday.("23:00:00"))

      assert %Decision{state: :heat} = decide(saturday.("22:30:00"), nil, windows)
      assert %Decision{state: :frost} = decide(saturday.("23:00:00"), nil, windows)
    end

    test "a missed edge is made up late" do
      assert %Decision{state: :heat} = decide(thursday("18:50:00"))
      assert %Decision{state: :frost} = decide(thursday("19:30:00"))
    end
  end

  describe "decide/4" do
    test "without windows or presses the heater stays in frost protection with nothing upcoming" do
      assert %Decision{state: :frost, until: nil} = decide(thursday("12:00:00"), nil, [])
    end

    test "frost protection says when the next window starts" do
      decision = decide(thursday("19:00:00"))
      assert %Decision{state: :frost, cause: :window} = decision
      assert_at(decision.until, at("2026-11-06", "07:00:00"))
    end

    test "the evening switch-off ends manual heating outside a window" do
      assert %Decision{state: :frost, cause: :evening} =
               decide(thursday("22:00:00"), press(:heat, thursday("20:15:00")))
    end

    test "manual heating inside a window that runs past 22:00 lasts until the window ends" do
      late = %Window{on_minute: 18 * 60, off_minute: 23 * 60, days: [4], enabled: true}
      event = press(:heat, thursday("21:00:00"))

      decision = decide(thursday("21:00:00"), event, [late])
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, thursday("23:00:00"))
    end

    test "manual frost protection outside a window lasts until the next window" do
      decision = decide(thursday("21:00:00"), press(:frost, thursday("20:59:00")))
      assert %Decision{state: :frost, cause: :manual, until: until} = decision
      assert_at(until, at("2026-11-06", "07:00:00"))
    end

    test "a paused window is no window" do
      paused = %{@weekdays | enabled: false}
      assert %Decision{state: :frost, until: nil} = decide(thursday("12:00:00"), nil, [paused])
    end

    test "an off time before the on time ends the next day" do
      night = %Window{on_minute: 22 * 60, off_minute: 6 * 60, days: [4], enabled: true}

      decision = decide(at("2026-11-06", "03:00:00"), nil, [night])
      assert %Decision{state: :heat, cause: :window} = decision
      assert_at(decision.until, at("2026-11-06", "06:00:00"))

      assert %Decision{state: :frost} = decide(at("2026-11-06", "06:00:00"), nil, [night])
    end

    test "back-to-back windows keep heating across the seam" do
      morning = %Window{on_minute: 7 * 60, off_minute: 12 * 60, days: [4], enabled: true}
      noon = %Window{on_minute: 12 * 60, off_minute: 15 * 60, days: [4], enabled: true}

      decision = decide(thursday("12:00:00"), nil, [morning, noon])
      assert %Decision{state: :heat, cause: :window} = decision
      assert_at(decision.until, thursday("15:00:00"))
    end

    test "overlapping windows heat as one until the last of them ends" do
      morning = %Window{on_minute: 7 * 60, off_minute: 12 * 60, days: [4], enabled: true}
      day = %Window{on_minute: 10 * 60, off_minute: 19 * 60, days: [4], enabled: true}

      decision = decide(thursday("11:00:00"), nil, [morning, day])
      assert %Decision{state: :heat, cause: :window} = decision
      assert_at(decision.until, thursday("19:00:00"))

      assert %Decision{state: :heat} = decide(thursday("12:00:00"), nil, [morning, day])
    end

    test "a press exactly at a window's end wins" do
      decision = decide(thursday("19:00:00"), press(:heat, thursday("19:00:00")))
      assert %Decision{state: :heat, cause: :manual} = decision
      assert_at(decision.until, thursday("22:00:00"))
    end

    test "a window that the spring gap turns inside out is skipped that day" do
      # 2027-03-28 is a Sunday; Berlin's clocks jump from 02:00 to 03:00.
      gap = %Window{on_minute: 2 * 60 + 30, off_minute: 3 * 60, days: [7], enabled: true}
      sunday = &at("2027-03-28", &1)

      assert %Decision{state: :frost, until: nil} = decide(sunday.("01:00:00"), nil, [gap])
      assert %Decision{state: :frost} = decide(sunday.("03:45:00"), nil, [gap])
    end

    test "windows follow the local wall clock across the end of summer time" do
      # 2026-10-25 is the Sunday the clocks go back in Berlin.
      sunday = %Window{on_minute: 7 * 60, off_minute: 9 * 60, days: [7], enabled: true}

      decision = decide(at("2026-10-24", "12:00:00"), nil, [sunday])
      assert_at(decision.until, at("2026-10-25", "07:00:00"))
      assert decision.until |> DateTime.shift_zone!(@zone) |> DateTime.to_time() == ~T[07:00:00]
    end
  end
end
