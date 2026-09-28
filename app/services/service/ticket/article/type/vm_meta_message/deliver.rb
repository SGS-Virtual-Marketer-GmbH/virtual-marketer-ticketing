# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Article::Type::VmMetaMessage::Deliver < Service::Ticket::Article::Type::BaseDeliver
  private

  def channel_adapter
    'vm_meta'.freeze
  end

  def check_channel!
    super

    error!(message: "Recipient id is missing in ticket.preferences['vm_meta']['sender_id'] for Ticket.find(#{ticket.id})") if !sender_id
  end

  def deliver_arguments
    {
      body:                      article.body,
      attachment:                article.attachments&.first,
      recipient_id:              sender_id,
      platform:                  platform,
      message_type:              message_type,
      last_customer_message_at:  last_customer_message_at,
    }
  end

  def handle_deliver_result
    article.preferences['vm_meta'] = {
      message_id: result[:id],
    }
    article.message_id = result[:id]
  end

  def message_type
    media? ? 'media' : 'text'
  end

  def media?
    article.attachments&.present?
  end

  def sender_id
    @sender_id ||= ticket.preferences.dig('vm_meta', 'sender_id')
  end

  def platform
    @platform ||= ticket.preferences.dig('vm_meta', 'platform')
  end

  # Meta's messaging.timestamp is epoch MILLISECONDS (unlike WhatsApp's Cloud
  # API, which uses epoch seconds) - see lib/vm_meta/webhook/message.rb's
  # docstring. This could not be verified against a live webhook in this
  # environment; re-check against a real payload before relying on the
  # 24h/7d window math in production.
  def last_customer_message_at
    timestamp = ticket.preferences.dig('vm_meta', 'timestamp_incoming')
    return if timestamp.blank?

    Time.zone.at(timestamp.to_i / 1000.0)
  end
end
