# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# A tap on a quick-reply button of a template message, e.g. "Ja, gerne" or
# "Keine Werbung" under a campaign. Without this class the webhook rejected
# the type and the customer's answer never reached the ticket.
class Whatsapp::Webhook::Message::Button < Whatsapp::Webhook::Message
  private

  def body
    message[:text].presence || message[:payload].to_s
  end

  def content_type
    'text/plain'
  end

  def type
    :button
  end

  def article_preferences
    super.merge(
      button:             { text: message[:text], payload: message[:payload] }.compact,
      context_message_id: raw_message.dig(:context, :id),
    ).compact
  end

  def raw_message
    @data[:entry].first[:changes].first[:value][:messages].first
  end
end
