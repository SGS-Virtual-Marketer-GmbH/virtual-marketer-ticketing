Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/vm_ticket_presence', to: 'vm_ticket_presence#show', via: :get
end
