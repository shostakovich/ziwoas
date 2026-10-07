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

  # Rails' API views exist only as .json.jbuilder: anything but JSON is a 406.
  pipeline :api do
    plug :accepts, ["json"]
  end

  # Turbo asks for text/vnd.turbo-stream.html first: these controllers answer
  # Turbo Streams or negotiate them themselves, as Rails' respond_to does.
  pipeline :turbo do
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ZiwoasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ZiwoasWeb.Look
    plug :put_format, "html"
  end

  scope "/", ZiwoasWeb do
    pipe_through :browser

    patch "/look", LookController, :update

    # Under the PV tab, because that is where the Wirtschaftlichkeit card reads them.
    get "/solakon/wirtschaftlichkeit", EconomicsController, :index
    post "/solakon/wirtschaftlichkeit/kosten", EconomicsController, :create_cost_item
    delete "/solakon/wirtschaftlichkeit/kosten/:id", EconomicsController, :delete_cost_item
    post "/solakon/wirtschaftlichkeit/preise", EconomicsController, :create_price
    delete "/solakon/wirtschaftlichkeit/preise/:id", EconomicsController, :delete_price

    live_session :default,
      on_mount: ZiwoasWeb.Nav,
      session: {ZiwoasWeb.Look, :session, []} do
      live "/", DashboardLive
      live "/solakon", SolakonLive
      live "/solakon/history", SolakonHistoryLive
      live "/weather", WeatherLive
      live "/reports", ReportsLive
      live "/sensors", SensorsLive
      live "/switches", SwitchesLive
      live "/lights/:key", LightLive
    end
  end

  scope "/", ZiwoasWeb do
    pipe_through :turbo

    get "/lights/:key/edit", LightController, :edit
    patch "/lights/:key", LightController, :update
    put "/lights/:key", LightController, :update
    post "/lights/:light_key/command", LightCommandController, :create

    # A Zeitfenster is addressed by its group, an Einzelschaltung by its rule.
    scope "/plugs/:plug_id" do
      post "/switch", PlugSwitchController, :create

      get "/switch_windows/new", SwitchWindowController, :new
      post "/switch_windows", SwitchWindowController, :create
      get "/switch_windows/:group_id/edit", SwitchWindowController, :edit
      patch "/switch_windows/:group_id/enabled", SwitchWindowController, :enabled
      patch "/switch_windows/:group_id", SwitchWindowController, :update
      put "/switch_windows/:group_id", SwitchWindowController, :update
      delete "/switch_windows/:group_id", SwitchWindowController, :delete

      get "/switch_rules/new", SwitchRuleController, :new
      post "/switch_rules", SwitchRuleController, :create
      get "/switch_rules/:id/edit", SwitchRuleController, :edit
      patch "/switch_rules/:id/enabled", SwitchRuleController, :enabled
      patch "/switch_rules/:id", SwitchRuleController, :update
      put "/switch_rules/:id", SwitchRuleController, :update
      delete "/switch_rules/:id", SwitchRuleController, :delete
    end
  end

  # Rails' `render json:` behind a form's CSRF check: no Accept filter, the token from
  # the X-CSRF-Token header or the form.
  pipeline :json_writes do
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ZiwoasWeb do
    pipe_through :json_writes

    patch "/solakon/eps", SolakonControlsController, :eps
    patch "/solakon/control", SolakonControlsController, :control
  end

  pipeline :health do
    plug :accepts, ["html", "json"]
  end

  scope "/", ZiwoasWeb do
    pipe_through :health

    get "/up", HealthController, :show
    get "/up.json", HealthController, :json_up
  end

  # Rails' `render json:` answers whatever the request accepts.
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
