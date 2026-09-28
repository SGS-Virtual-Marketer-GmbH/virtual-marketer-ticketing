# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Resolves a contact's display name from the Graph API:
#   Messenger:  GET /{psid}?fields=first_name,last_name
#   Instagram:  GET /{igsid}?fields=name,username
#
# Must never raise into the webhook flow - a failed lookup falls back to a
# generic display name (see VmMeta::Webhook::Message#profile_name), the
# webhook itself must never fail because of this.
class VmMeta::Graph::Profile

  def initialize(access_token:, platform:)
    @access_token = access_token
    @platform     = platform
  end

  def name(sender_id)
    data = client.get(sender_id.to_s, fields: fields_param)

    platform_messenger? ? messenger_name(data) : instagram_name(data)
  end

  private

  attr_reader :access_token, :platform

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
