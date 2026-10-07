defmodule ZiwoasWeb.Plugs.RequireConfigTest do
  use ZiwoasWeb.ConnCase, async: false

  alias Ziwoas.{Config, TestConfigs}

  setup do
    TestConfigs.put(Config.from_yaml("location: nope\n"))
    :ok
  end

  for path <- ~w(/ /solakon /solakon/history /solakon/wirtschaftlichkeit /weather /reports
                 /sensors /switches /lights/any) do
    test "#{path} is a 503 naming the config error", %{conn: conn} do
      error =
        conn
        |> get(unquote(path))
        |> html_response(503)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#config-error")
        |> LazyHTML.text()

      assert error =~ "location"
    end
  end
end
