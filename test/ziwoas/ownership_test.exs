defmodule Ziwoas.OwnershipTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Ownership
  alias Ziwoas.Ownership.NotOwnerError

  setup do
    on_exit(&Ownership.clear_override/0)
  end

  test "the test config has no section: every task stays with rails" do
    assert Ownership.owners() == Ownership.all_rails()
    refute Ownership.runs?(:weather)
  end

  test "the config carries its migration section" do
    config =
      Ziwoas.TestConfigs.plugs("""
      migration:
        owners:
          weather: shadow
          switching: dry_run
      """)

    assert config.owners.weather == :shadow
    assert config.owners.switching == :dry_run
    assert config.owners.aggregator == :rails
    assert Ownership.mode(:switching, config.owners) == :dry_run
  end

  test "a bad section stops the config like any other check" do
    assert_raise Ziwoas.Config.Error,
                 "migration.owners.weather must be one of rails, shadow, phoenix",
                 fn ->
                   Ziwoas.TestConfigs.plugs("migration:\n  owners:\n    weather: dry_run\n")
                 end
  end

  test "the modes answer what Phoenix may do" do
    Ownership.override(%{weather: :shadow, switching: :dry_run, economics: :phoenix})

    assert {Ownership.runs?(:aggregator), Ownership.owner?(:aggregator)} == {false, false}
    assert {Ownership.runs?(:weather), Ownership.owner?(:weather)} == {true, false}

    assert {Ownership.runs?(:switching), Ownership.may_write_devices?(:switching)} ==
             {true, false}

    assert {Ownership.owner?(:economics), Ownership.may_write_devices?(:economics)} ==
             {true, true}
  end

  test "ensure_owner! lets only the owner through" do
    Ownership.override(%{lights: :phoenix, switching: :dry_run, weather: :shadow})

    assert Ownership.ensure_owner!(:lights) == :ok

    for task <- [:switching, :weather, :solakon_control] do
      error = assert_raise NotOwnerError, fn -> Ownership.ensure_owner!(task) end
      assert error.task == task
    end

    assert_raise NotOwnerError,
                 "switching runs in dry_run mode here: Phoenix does not own it",
                 fn ->
                   Ownership.ensure_owner!(:switching)
                 end
  end

  test "writes go to main as owner, to the shadow in shadow and dry run, nowhere for rails" do
    Ownership.override(%{economics: :phoenix, weather: :shadow, switching: :dry_run})

    assert Ownership.write_target(:economics) == :main
    assert Ownership.write_target(:weather) == :shadow
    assert Ownership.write_target(:switching) == :shadow
    assert_raise NotOwnerError, fn -> Ownership.write_target(:aggregator) end
  end

  test "an unknown task is a programming error" do
    assert_raise ArgumentError, "unknown task :wether", fn -> Ownership.mode(:wether) end
  end

  test "a process the test starts sees its owners" do
    Ownership.override(%{weather: :phoenix})
    task = Task.async(fn -> Ownership.mode(:weather) end)
    assert Task.await(task) == :phoenix
  end
end
