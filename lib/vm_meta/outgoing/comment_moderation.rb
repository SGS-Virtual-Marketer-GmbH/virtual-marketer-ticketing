# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# What an agent can do with a customer's public comment besides answering it
# publicly: hide it, show it again, or answer it privately.
#
#   hide    Facebook:  POST /{comment_id}  is_hidden=true   (pages_manage_engagement)
#           Instagram: POST /{comment_id}  hide=true        (instagram_manage_comments)
#   private POST /{page_id}/messages  recipient={comment_id}   (both platforms, as for
#           ordinary direct messages: Instagram is reached through its Page)
#           Meta allows ONE private reply per comment, within 7 days of it,
#           and only while the commenter has not messaged the page since.
class VmMeta::Outgoing::CommentModeration

  PRIVATE_REPLY_WINDOW = 7.days

  attr_reader :options, :platform

  def initialize(options:, platform:)
    @options  = options
    @platform = platform
  end

  def hide(comment_id:, hidden: true)
    params = platform == 'instagram' ? { hide: hidden } : { is_hidden: hidden }
    client.post(comment_id.to_s, params)

    true
  end

  def private_reply(comment_id:, body:)
    response = client.post("#{options[:page_id]}/messages", {
      recipient: { comment_id: comment_id.to_s },
      message:   { text: body },
    })

    { id: response['message_id'] || response['id'] }
  end

  private

  def client
    @client ||= VmMeta::Graph::Client.new(access_token: options[:page_access_token])
  end
end
