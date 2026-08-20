Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/vm_team_stats', to: 'vm_team_stats#show', via: :get
end
