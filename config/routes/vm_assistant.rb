Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # The UI's only way to reach the Virtual Marketer assistant. Deliberately a
  # single endpoint: the browser sends a message, the server decides who sent
  # it. See VmAssistantController for why that split matters.
  match api_path + '/vm_assistant/chat', to: 'vm_assistant#chat', via: :post

  # The ticket-zoom sidebar's customer-context card — see
  # VmAssistantController#customer_profile.
  match api_path + '/vm_assistant/customer_profile', to: 'vm_assistant#customer_profile', via: :get
end
