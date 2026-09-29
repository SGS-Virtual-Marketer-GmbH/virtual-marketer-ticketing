# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# The customer's answer to an interactive message: a reply button
# (button_reply), a list entry (list_reply) or a submitted flow (nfm_reply).
# The visible title becomes the article body; the machine-readable id stays in
# the article preferences for anyone who needs to tell the choices apart.
class Whatsapp::Webhook::Message::Interactive < Whatsapp::Webhook::Message
  private

  def body
    case reply_type
    when 'button_reply', 'list_reply'
      [reply[:title], reply[:description]].compact_blank.join("\n").presence || reply[:id].to_s
    when 'nfm_reply'
      flow_body
    else
      reply_type.to_s
    end
  end

  def content_type
    'text/plain'
  end

  def type
    :interactive
  end

  def reply_type
    message[:type]
  end

  def reply
    message[reply_type&.to_sym] || {}
  end

  def flow_body
    response = JSON.parse(reply[:response_json].to_s)
    lines = response.except('flow_token').map { |key, value| "#{key}: #{value}" }
    [reply[:body].presence, *lines].compact.join("\n").presence || reply[:name].to_s
  rescue JSON::ParserError
    reply[:body].presence || reply[:name].to_s
  end

  def article_preferences
    super.merge(
      interactive:        { type: reply_type, id: reply[:id], title: reply[:title], name: reply[:name] }.compact,
      context_message_id: raw_message.dig(:context, :id),
    ).compact
  end

  def raw_message
    @data[:entry].first[:changes].first[:value][:messages].first
  end
end
