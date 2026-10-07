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
    plug ZiwoasWeb.Plugs.RequireConfig
  end

  scope "/", ZiwoasWeb do
    pipe_through :browser

    live_session :default,
      on_mount: ZiwoasWeb.Nav,
      session: {ZiwoasWeb.Look, :session, []} do
      live "/", DashboardLive
      live "/solakon", SolakonLive
      live "/solakon/history", SolakonHistoryLive
      live "/solakon/wirtschaftlichkeit", EconomicsLive
      live "/weather", WeatherLive
      live "/reports", ReportsLive
      live "/sensors", SensorsLive
      live "/switches", SwitchesLive
      live "/lights/:key", LightLive
    end
  end

  scope "/", ZiwoasWeb do
    get "/up", HealthController, :show
  end
end
