Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/vm_customer_history', to: 'vm_customer_history#show', via: :get
end
