defmodule ZiwoasWeb.PlushTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.Plush

  test "every plush name points at an image in priv/static" do
    for name <- Plush.names() do
      "/images/" <> file = Plush.src(name, :light)
      assert File.exists?(Path.join("priv/static/images", file)), "#{name}: #{file} is missing"
    end
  end

  test "names follow Lucide, the off image of a pair and the weather by condition and daytime" do
    assert Plush.src("house", :light) == "/images/nav_dashboard_plush.webp"
    assert Plush.src("lamp-ceiling-off", :light) == "/images/lamp_ceiling_off.webp"

    assert Plush.src("weather-partly-cloudy-night", :light) ==
             "/images/weather_partly_cloudy_night.webp"
  end

  test "has no dark images and nothing for an unknown name" do
    assert Plush.src("house", :dark) == nil
    assert Plush.src("rocket", :light) == nil
  end
end
