# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Channel::Driver::VmMeta
  def deliver(options, attr, _notification = false)
    return true if Setting.get('import_mode')

    # Public comment reply: its own path, none of the direct-message window logic.
    if attr[:message_type] == 'comment'
      return VmMeta::Outgoing::Comment.new(options:, platform: attr[:platform], comment_id: attr[:comment_id]).deliver(body: attr[:body])
    end

    message = "VmMeta::Outgoing::Message::#{attr[:message_type].capitalize}".constantize.new(
      options:,
      recipient_id:              attr[:recipient_id],
      platform:                  attr[:platform],
      last_customer_message_at:  attr[:last_customer_message_at],
    )

    if attr[:message_type] == 'text'
      return message.deliver(body: attr[:body])
    end

    message.deliver(body: attr[:body], attachment: attr[:attachment])
  end
end
