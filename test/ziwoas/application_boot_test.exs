defmodule Ziwoas.ApplicationBootTest do
  # Changes the config path and the boot owners, both VM-wide.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ziwoas.{Config, Ownership}

  @moduletag :tmp_dir

  setup do
    previous_path = Application.fetch_env!(:ziwoas, :config_path)
    previous_owners = Ownership.owners()

    on_exit(fn ->
      Application.put_env(:ziwoas, :config_path, previous_path)
      Config.reset()
      Ownership.put_boot_owners(previous_owners)
    end)
  end

  test "a config that fails at boot leaves Phoenix owning nothing, even once it loads",
       %{tmp_dir: dir} do
    Application.put_env(:ziwoas, :config_path, Path.join(dir, "missing.yml"))
    Config.reset()

    {result, log} = with_log(fn -> Ziwoas.Application.boot_config() end)

    assert {nil, owners} = result
    assert log =~ "config: config file not found; Phoenix owns no task"
    assert owners == Ownership.all_rails()
    Ownership.put_boot_owners(owners)

    fixed = Path.join(dir, "ziwoas.yml")
    inverter = Ziwoas.TestConfigs.file(:inverter)
    File.write!(fixed, File.read!(inverter) <> "\nmigration:\n  owners:\n    weather: phoenix\n")
    Application.put_env(:ziwoas, :config_path, fixed)
    Config.reset()

    assert Config.app_config().owners.weather == :phoenix
    assert Ownership.owners() == Ownership.all_rails()
    refute Ownership.runs?(:weather)
  end

  test "a readable config hands its owners to the boot" do
    config = Config.app_config()

    assert Ziwoas.Application.boot_config(fn -> config end) == {config, config.owners}
  end
end
