defmodule Ziwoas.RailsFixtureTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "never deletes a database outside tmp/ (ZIWOAS_DB=<file> mix test)" do
    outside =
      Path.join(
        System.tmp_dir!(),
        "ziwoas-fixture-guard-#{System.unique_integer([:positive])}.sqlite3"
      )

    File.write!(outside, "precious")
    on_exit(fn -> File.rm(outside) end)

    assert_raise RuntimeError, ~r/under .*tmp only/, fn -> Ziwoas.RailsFixture.build!(outside) end
    assert File.read!(outside) == "precious"
  end

  test "a symlink inside tmp that points outside is refused too", %{tmp_dir: dir} do
    outside =
      Path.join(
        System.tmp_dir!(),
        "ziwoas-fixture-link-#{System.unique_integer([:positive])}.sqlite3"
      )

    File.write!(outside, "precious")
    on_exit(fn -> File.rm(outside) end)
    File.ln_s!(outside, Path.join(dir, "link.sqlite3"))

    assert_raise RuntimeError, fn ->
      Ziwoas.RailsFixture.build!(Path.join(dir, "link.sqlite3"))
    end

    assert File.read!(outside) == "precious"
  end

  test "builds under tmp", %{tmp_dir: dir} do
    path = Path.join(dir, "built.sqlite3")

    assert Ziwoas.RailsFixture.build!(path, rows: false) == path
  end
end
