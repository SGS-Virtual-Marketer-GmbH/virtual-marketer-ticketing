# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/channels_vm_meta_webhook/:callback_url_uuid', to: 'channels_vm_meta#verify_webhook',  via: :get
  match api_path + '/channels_vm_meta_webhook/:callback_url_uuid', to: 'channels_vm_meta#perform_webhook', via: :post

  match api_path + '/channels_admin/vm_meta',     to: 'channels_admin/vm_meta#index',  via: :get
  match api_path + '/channels_admin/vm_meta',     to: 'channels_admin/vm_meta#create', via: :post
  match api_path + '/channels_admin/vm_meta/:id', to: 'channels_admin/vm_meta#update', via: :put
end
