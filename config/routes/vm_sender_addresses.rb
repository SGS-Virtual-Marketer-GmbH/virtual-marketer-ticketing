Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # Choose the sender address when replying by email. See
  # VmSenderAddressesController.
  match api_path + '/vm_sender_addresses', to: 'vm_sender_addresses#index', via: :get
end
