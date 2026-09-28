# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Adds certain (missing) meta data when creating messenger/instagram
# articles - mirrors Ticket::Article::AddsMetadataWhatsapp so an agent reply
# (which, like WhatsappReply's coffee action, does not set 'from'/'to'
# itself) still gets a sensible From/To shown in the article header.
module Ticket::Article::AddsMetadataVmMeta
  extend ActiveSupport::Concern

  VM_META_TYPES = ['messenger message', 'instagram message'].freeze

  included do
    before_create :ticket_article_add_metadata_vm_meta
  end

  private

  def ticket_article_add_metadata_vm_meta
    return if !neither_importing_nor_postmaster?
    return if !sender_needs_metadata?
    return if !type_vm_meta_needs_metadata?

    metadata_vm_meta_process_from_and_to
  end

  def type_vm_meta_needs_metadata?
    return false if !type_id

    type = Ticket::Article::Type.lookup(id: type_id)
    return false if type.nil?

    Ticket::Article::AddsMetadataVmMeta::VM_META_TYPES.include?(type.name)
  end

  def vm_meta_platform_label
    ticket.preferences.dig('vm_meta', 'platform') == 'instagram' ? 'Instagram' : 'Facebook Messenger'
  end

  def vm_meta_from_name(channel)
    channel_label = channel.options[:name].presence || vm_meta_platform_label

    if created_by_id != 1
      return "#{created_by.firstname} #{created_by.lastname} via #{channel_label}"
    end

    channel_label
  end

  def vm_meta_to_name
    ticket.preferences.dig('vm_meta', 'contact_ref').presence || ticket.customer&.fullname
  end

  def metadata_vm_meta_process_from_and_to
    channel = Channel.lookup(id: ticket.preferences['channel_id'])

    return if !channel

    self.from = vm_meta_from_name(channel)
    self.to = vm_meta_to_name
  end
end
