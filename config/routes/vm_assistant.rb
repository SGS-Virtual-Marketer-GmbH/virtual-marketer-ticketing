Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # The UI's only way to reach the Virtual Marketer assistant. Deliberately a
  # single endpoint: the browser sends a message, the server decides who sent
  # it. See VMAssistantController for why that split matters.
  match api_path + '/vm_assistant/chat', to: 'vm_assistant#chat', via: :post
end
