defmodule ZiwoasWeb.Router do
  use ZiwoasWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ZiwoasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ZiwoasWeb.Look
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ZiwoasWeb do
    pipe_through :browser

    patch "/look", LookController, :update

    live_session :default,
      on_mount: ZiwoasWeb.Nav,
      session: {ZiwoasWeb.Look, :session, []} do
      live "/", DashboardLive
      live "/solakon", SolakonLive
      live "/solakon/history", SolakonHistoryLive
      # Under the PV tab, because that is where the Wirtschaftlichkeit card reads them.
      live "/solakon/wirtschaftlichkeit", EconomicsLive
      live "/weather", WeatherLive
      live "/reports", ReportsLive
      live "/sensors", SensorsLive
      live "/switches", SwitchesLive
      live "/lights/:key", LightLive
    end
  end

  pipeline :health do
    plug :accepts, ["html", "json"]
  end

  scope "/", ZiwoasWeb do
    pipe_through :health

    get "/up", HealthController, :show
    get "/up.json", HealthController, :json_up
  end

  # The Sensoren chart's data: JSON whatever the request accepts.
  scope "/", ZiwoasWeb do
    get "/sensors/series", SensorsController, :series
  end

  scope "/api", ZiwoasWeb do
    pipe_through :api

    get "/today", ApiController, :today
    get "/today/summary", ApiController, :today_summary
    get "/history", ApiController, :history
  end
end
