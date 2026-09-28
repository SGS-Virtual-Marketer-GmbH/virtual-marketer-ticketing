Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # "Send an approved template" -- re-opens a WhatsApp conversation once the
  # 24 hour customer service window has closed. See
  # VmWhatsappTemplatesController.
  match api_path + '/vm_whatsapp/templates', to: 'vm_whatsapp_templates#index', via: :get
  match api_path + '/vm_whatsapp/templates/send', to: 'vm_whatsapp_templates#send_template', via: :post
end
