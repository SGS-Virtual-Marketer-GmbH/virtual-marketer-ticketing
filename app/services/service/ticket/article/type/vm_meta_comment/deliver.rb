# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Article::Type::VmMetaComment::Deliver < Service::Ticket::Article::Type::BaseDeliver
  private

  def channel_adapter
    'vm_meta'.freeze
  end

  def check_channel!
    super

    error!(message: "Comment thread id is missing in ticket.preferences['vm_meta_comment']['thread_id'] for Ticket.find(#{ticket.id})") if !thread_id
  end

  def deliver_arguments
    {
      body:         article.body,
      message_type: 'comment',
      platform:     ticket.preferences.dig('vm_meta_comment', 'platform'),
      comment_id:   thread_id,
    }
  end

  def handle_deliver_result
    article.preferences['vm_meta'] = {
      message_id: result[:id],
    }
    article.message_id = result[:id]
  end

  def thread_id
    @thread_id ||= ticket.preferences.dig('vm_meta_comment', 'thread_id')
  end
end
