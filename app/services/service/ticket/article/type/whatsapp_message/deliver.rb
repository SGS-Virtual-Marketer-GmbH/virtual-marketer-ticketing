# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Article::Type::WhatsappMessage::Deliver < Service::Ticket::Article::Type::BaseDeliver
  private

  def channel_adapter
    'whatsapp'.freeze
  end

  def check_channel!
    super

    error!(message: "Recipient phone number is missing in ticket.preferences['whatsapp']['from']['phone_number'] for Ticket.find(#{ticket.id})") if !from_phone_number
  end

  def deliver_arguments
    {
      body:                article.body,
      attachment:          article.attachments&.first,
      recipient_number:    from_phone_number,
      message_type:        message_type,
      template_name:       template_preferences&.dig('name'),
      template_language:   template_preferences&.dig('language'),
      template_components: template_preferences&.dig('components_json'),
    }
  end

  def handle_deliver_result
    article.preferences['whatsapp'] = {
      message_id: result[:id],
    }
    article.message_id = result[:id]
  end

  def message_type
    return 'template' if template_preferences.present?

    media? ? 'media' : 'text'
  end

  def media?
    article.attachments&.present?
  end

  # Set by VmWhatsappTemplatesController#send when the article is a
  # Meta-approved template reply rather than free-form text/media -- see
  # that controller for how name/language/components_json are built.
  def template_preferences
    @template_preferences ||= article.preferences['vm_whatsapp_template']
  end

  def from_phone_number
    @from_phone_number ||= ticket.preferences.dig('whatsapp', 'from', 'phone_number')
  end
end
