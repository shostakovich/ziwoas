Rails.application.routes.draw do
  root "dashboard#index"

  resource :look, only: :update

  get "/reports", to: "reports#index"
  get "/weather", to: "weather#index"
  get "/sensors", to: "sensors#index", as: :sensors
  get "/sensors/series", to: "sensors#series", as: :sensors_series

  get "/switches", to: "switches#index", as: :switches
  resources :lights, param: :key, only: %i[show edit update]

  get "/solakon", to: "solakon#index", as: :solakon
  get "/solakon/history", to: "solakon#history", as: :solakon_history
  patch "/solakon/eps", to: "solakon_controls#eps", as: :solakon_eps
  patch "/solakon/control", to: "solakon_controls#control", as: :solakon_control

  # Under the PV tab, because that is where the Wirtschaftlichkeit card reads them.
  get "/solakon/wirtschaftlichkeit", to: "economics#index", as: :economics
  resources :cost_items, only: %i[create destroy], path: "/solakon/wirtschaftlichkeit/kosten"
  resources :electricity_prices, only: %i[create destroy], path: "/solakon/wirtschaftlichkeit/preise"

  scope "/plugs/:plug_id" do
    post "switch", to: "plug_switches#create", as: :plug_switch
    # A Zeitfenster is addressed by its group, an Einzelschaltung by its rule.
    resources :switch_windows, param: :group_id, only: %i[new create edit update destroy] do
      patch :enabled, on: :member
    end
    resources :switch_rules, only: %i[new create edit update destroy] do
      patch :enabled, on: :member
    end
  end

  scope "/lights/:light_key" do
    post "command", to: "lights#command", as: :light_command
  end

  get "/api/today", to: "api#today"
  get "/api/today/summary", to: "api#today_summary"
  get "/api/history", to: "api#history"

  get "up" => "rails/health#show", as: :rails_health_check
end
