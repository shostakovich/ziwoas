defmodule Ziwoas.ApplicationBootTest do
  # Changes the config path, which is VM-wide.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ziwoas.Config

  @moduletag :tmp_dir

  setup do
    previous_path = Application.fetch_env!(:ziwoas, :config_path)

    on_exit(fn ->
      Application.put_env(:ziwoas, :config_path, previous_path)
      Config.reset()
    end)
  end

  test "a config that fails at boot starts no collector and no scheduler", %{tmp_dir: dir} do
    Application.put_env(:ziwoas, :config_path, Path.join(dir, "missing.yml"))
    Config.reset()

    {result, log} = with_log(fn -> Ziwoas.Application.boot_config() end)

    assert result == nil
    assert log =~ "config: config file not found; no collector, no scheduler"
  end

  test "a readable config is what the collector and the scheduler start from" do
    config = Config.app_config()

    assert Ziwoas.Application.boot_config(fn -> config end) == config
  end
end
