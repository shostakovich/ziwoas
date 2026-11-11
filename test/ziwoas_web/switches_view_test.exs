defmodule ZiwoasWeb.SwitchesViewTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.SwitchesView

  test "a view and its parameter go both ways" do
    for view <- [:all, :favourites, :none, {:room, 7}] do
      assert view |> SwitchesView.to_param() |> SwitchesView.parse() == view
    end
  end

  test "an unknown parameter names no view" do
    for param <- [nil, "", "quatsch", "0", "-1", "7x"] do
      assert SwitchesView.parse(param) == nil
    end
  end

  test "the way back leads to the view, else to Schalten" do
    assert SwitchesView.back_path("7") == "/switches?raum=7"
    assert SwitchesView.back_path("favoriten") == "/switches?raum=favoriten"
    assert SwitchesView.back_path(nil) == "/switches"
    assert SwitchesView.back_path("quatsch") == "/switches"
  end
end
