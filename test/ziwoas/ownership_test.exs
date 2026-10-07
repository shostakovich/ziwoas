defmodule Ziwoas.OwnershipTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Ownership
  alias Ziwoas.Ownership.NotOwnerError

  test "Phoenix owns every task" do
    assert Ownership.owners() |> Map.values() |> Enum.uniq() == [:phoenix]
    assert map_size(Ownership.owners()) == length(Ownership.tasks())

    for {task, _class} <- Ownership.tasks() do
      assert Ownership.runs?(task)
      assert Ownership.owner?(task)
      assert Ownership.acting?(task)
      assert Ownership.may_write_devices?(task)
      assert Ownership.ensure_owner!(task) == :ok
    end
  end

  test "the config carries its migration section, which decides nothing any more" do
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
    assert Ownership.mode(:switching) == :phoenix
  end

  test "a bad section stops the config like any other check" do
    assert_raise Ziwoas.Config.Error,
                 "migration.owners.weather must be one of rails, shadow, phoenix",
                 fn ->
                   Ziwoas.TestConfigs.plugs("migration:\n  owners:\n    weather: dry_run\n")
                 end
  end

  test "the error for a task Phoenix does not own names its mode" do
    assert Exception.message(%NotOwnerError{task: :switching, mode: :dry_run}) ==
             "switching runs in dry_run mode here: Phoenix does not own it"
  end

  test "an unknown task is a programming error" do
    assert_raise ArgumentError, "unknown task :wether", fn -> Ownership.mode(:wether) end
  end
end
