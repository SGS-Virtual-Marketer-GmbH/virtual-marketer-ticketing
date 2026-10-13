# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Resolves a contact's display name from the Graph API:
#   Messenger:  GET /{psid}?fields=first_name,last_name
#   Instagram:  GET /{igsid}?fields=name,username
#
# Meta restricts the direct profile lookup (Messenger above all: it answers
# "does not exist or missing permissions" for ordinary customers while the
# message itself is fine). The conversation the contact started names its
# participants without that restriction, so that is the fallback:
#   GET /{page_id}/conversations?platform=...&user_id={id}&fields=participants
#
# Must never raise into the webhook flow - a failed lookup falls back to a
# generic display name (see VmMeta::Webhook::Message#profile_name), the
# webhook itself must never fail because of this.
class VmMeta::Graph::Profile

  def initialize(access_token:, platform:, page_id: nil)
    @access_token = access_token
    @platform     = platform
    @page_id      = page_id
  end

  def name(sender_id)
    direct_name(sender_id) || conversation_name(sender_id)
  end

  private

  attr_reader :access_token, :platform, :page_id

  def direct_name(sender_id)
    data = client.get(sender_id.to_s, fields: fields_param)

    platform_messenger? ? messenger_name(data) : instagram_name(data)
  rescue VmMeta::Graph::Client::GraphAPIError => e
    Rails.logger.info "VmMeta profile - direct lookup refused (#{e.message.to_s[0, 120]}), asking the conversation instead"
    nil
  end

  def conversation_name(sender_id)
    return if page_id.blank?

    data = client.get(
      "#{page_id}/conversations",
      platform: platform_messenger? ? 'messenger' : 'instagram',
      user_id:  sender_id.to_s,
      fields:   'participants',
    )

    participants = Array(data['data']).flat_map { |conversation| Array(conversation.dig('participants', 'data')) }
    participant  = participants.find { |entry| entry['id'].to_s == sender_id.to_s }

    participant && (participant['name'].presence || participant['username'].presence)
  end

  def platform_messenger?
    platform == 'messenger'
  end

  def client
    @client ||= VmMeta::Graph::Client.new(access_token:)
  end

  def fields_param
    platform_messenger? ? 'first_name,last_name' : 'name,username'
  end

  def messenger_name(data)
    [data['first_name'], data['last_name']].reject(&:blank?).join(' ').presence
  end

  def instagram_name(data)
    data['name'].presence || data['username'].presence
  end
end
