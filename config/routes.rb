Rails.application.routes.draw do
  post "/planning-sessions", to: "planning_sessions#create"
  get "/planning-sessions/:id", to: "planning_sessions#show"
  patch "/planning-sessions/:id/travel-dna", to: "planning_sessions#update_dna"
  post "/planning-sessions/:id/clarifications", to: "planning_sessions#clarifications"
  post "/planning-sessions/:id/futures", to: "futures#create"
  get "/planning-sessions/:id/futures", to: "futures#index"
  get "/futures/:id", to: "futures#show"
  post "/futures/:id/simulations", to: "simulations#create"
  get "/futures/:id/forecast", to: "forecasts#show"
  post "/futures/:future_id/risks/:risk_id/mitigations/:mitigation_id", to: "mitigations#create"
  get "/jobs/:id", to: "jobs#show"
end
