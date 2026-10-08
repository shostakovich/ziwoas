defmodule Ziwoas.SolakonTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Repo, Solakon, TestConfigs}
  alias Ziwoas.Solakon.{PvHour, Snapshot}

  describe "the Auto-Regelung switch" do
    test "pauses and resumes the stored control" do
      config = TestConfigs.load(:inverter)

      assert Solakon.control_active?()
      assert Solakon.set_control_active(config, false) == {:ok, false}
      refute Solakon.control_active?()
      assert Solakon.set_control_active(config, true) == {:ok, true}
      assert Solakon.control_active?()
    end

    test "refuses without an inverter or with control switched off in the config" do
      config = TestConfigs.load(:inverter)

      assert Solakon.set_control_active(%{config | solakon: nil}, false) ==
               {:error, :not_configured}

      off = %{config | solakon: %{config.solakon | control_enabled: false}}
      assert Solakon.set_control_active(off, false) == {:error, :disabled}
      assert Solakon.control_active?()
    end
  end

  test "an outlet switch without a monitor is an error, not a crash" do
    assert {:error, {:monitor_down, _}} = Solakon.set_eps_output(true, :no_monitor)
  end

  test "the newest snapshot, and the PV hours of a range with its end left out" do
    for at <- [~U[2026-06-20 10:00:00.000000Z], ~U[2026-06-20 11:00:00.000000Z]] do
      Repo.insert!(%Snapshot{taken_at: at})
      Repo.insert!(%PvHour{started_at: at, pv_power_w: 100.0, reading_count: 120})
    end

    assert %Snapshot{taken_at: ~U[2026-06-20 11:00:00.000000Z]} = Solakon.latest_snapshot()
    assert Solakon.latest_pv_hour_start() == ~U[2026-06-20 11:00:00.000000Z]

    assert [%PvHour{started_at: ~U[2026-06-20 10:00:00.000000Z]}] =
             Solakon.pv_hours_between(
               ~U[2026-06-20 10:00:00.000000Z],
               ~U[2026-06-20 11:00:00.000000Z]
             )

    assert length(Solakon.pv_hours()) == 2
  end
end
