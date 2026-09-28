# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class VmMeta::Outgoing::Message::Text < VmMeta::Outgoing::Message
  def deliver(body:)
    params = {
      recipient: { id: recipient_id },
      message:   { text: body },
    }.merge(messaging_type_params)

    response = client.post("#{page_id}/messages", params)

    { id: response['message_id'] }
  end
end
