Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/vm_counts', to: 'vm_counts#index', via: :get
end
