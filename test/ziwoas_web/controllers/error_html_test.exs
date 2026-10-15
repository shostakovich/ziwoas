defmodule ZiwoasWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(ZiwoasWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(ZiwoasWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end

  test "the config error names the message in an error alert, as the loader wrote it" do
    doc =
      ZiwoasWeb.ErrorHTML
      |> render_to_string("config_error", "html", message: "location: expected a map\n  line 1")
      |> LazyHTML.from_fragment()

    assert doc |> LazyHTML.query("h1") |> LazyHTML.text() =~ "Gerätekonfiguration"

    assert doc |> LazyHTML.query("[role=alert] pre#config-error") |> LazyHTML.text() ==
             "location: expected a map\n  line 1"
  end
end
