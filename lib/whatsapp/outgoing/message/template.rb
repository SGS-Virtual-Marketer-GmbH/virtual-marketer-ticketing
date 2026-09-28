# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Whatsapp::Outgoing::Message::Template < Whatsapp::Outgoing::Message
  def deliver(name:, language:, components_json:)
    response = messages_api.send_template(
      sender_id:        phone_number_id.to_i,
      recipient_number: recipient_number.to_i,
      name:,
      language:,
      # send_template raises if both components and components_json are nil,
      # so an empty array (no placeholders) is passed explicitly rather than
      # left nil.
      components_json:  components_json.presence || [],
    )

    handle_response(response:)
  rescue WhatsappSdk::Api::Responses::HttpResponseError => e
    handle_error(response: e)
  end
end
