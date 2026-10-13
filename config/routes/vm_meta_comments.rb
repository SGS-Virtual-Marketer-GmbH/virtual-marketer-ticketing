Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # Hide / privately answer a public Facebook or Instagram comment. See
  # VmMetaCommentsController.
  match api_path + '/vm_meta_comments/:ticket_id/hide',          to: 'vm_meta_comments#hide',          via: :post
  match api_path + '/vm_meta_comments/:ticket_id/private_reply', to: 'vm_meta_comments#private_reply', via: :post
end
