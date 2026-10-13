# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# A public reply under a customer's comment. Unlike a direct message there is
# no reply window: Meta lets a Page/IG account answer a comment as long as it
# exists. Both platforms thread flat, so the reply always goes to the thread's
# ROOT comment.
#   Facebook:  POST /{comment_id}/comments  message=...
#   Instagram: POST /{comment_id}/replies   message=...
# (Facebook needs pages_manage_engagement, Instagram instagram_manage_comments.)
class VmMeta::Outgoing::Comment

  attr_reader :options, :platform, :comment_id

  def initialize(options:, platform:, comment_id:)
    @options    = options
    @platform   = platform
    @comment_id = comment_id
  end

  def deliver(body:)
    edge     = platform == 'instagram' ? 'replies' : 'comments'
    response = client.post("#{comment_id}/#{edge}", { message: body })

    { id: response['id'] }
  end

  private

  def client
    @client ||= VmMeta::Graph::Client.new(access_token: options[:page_access_token])
  end
end
