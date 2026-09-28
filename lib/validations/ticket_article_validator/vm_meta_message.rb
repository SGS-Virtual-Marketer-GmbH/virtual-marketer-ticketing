# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Validations::TicketArticleValidator
  class VmMetaMessage < Backend
    MATCHING_TYPES = ['messenger message', 'instagram message'].freeze

    # Meta's own hard limits: Messenger caps a text message at 2000
    # characters, Instagram Direct at 1000.
    MAX_TEXT_LENGTH = {
      'messenger message' => 2_000,
      'instagram message' => 1_000,
    }.freeze

    def validate_attachments_limit
      return if !all_attachments.many?

      @record.errors.add :base, format(__('Only %s attachment allowed'), 1)
    end

    def validate_instagram_attachments
      return if type_name != 'instagram message'
      return if !attachment

      @record.errors.add :base, __('Instagram Direct does not support file attachments in outgoing messages.')
    end

    def validate_attachments_size
      return if !attachment
      return if type_name == 'instagram message' # already rejected above

      attachment_size = attachment.size.to_i
      max_size        = 25 * 1024 * 1024

      return if attachment_size <= max_size

      message = format(__('File is too big. It has to be %s or smaller.'), ActiveSupport::NumberHelper.number_to_human_size(max_size))

      @record.errors.add :base, message
    end

    def validate_body
      return if attachment
      return if @record.body.present?

      @record.errors.add :base, __('Text or attachment is required')
    end

    def validate_body_length
      return if @record.body.blank?

      max_length = MAX_TEXT_LENGTH.fetch(type_name, 2_000)
      return if @record.body.length <= max_length

      @record.errors.add :base, format(__('Text is too long. Maximum length is %s characters.'), max_length)
    end

    def validate_ticket_state
      return if Ticket::State.where(name: %w[closed merged removed]).pluck(:id).exclude?(@record.ticket.state_id)

      @record.errors.add :base, __('Reply allowed only for open tickets')
    end

    private

    def type_name
      @type_name ||= Ticket::Article::Type.lookup(id: @record.type_id)&.name
    end

    def attachment
      return @attachment if defined?(@attachment)

      @attachment = all_attachments.first
    end

    def all_attachments
      @all_attachments ||= @record.attachments + (@record.instance_variable_get(:@attachments_buffer) || [])
    end

    def validator_applies?
      sender = Ticket::Article::Sender.lookup id: @record.sender_id

      sender.name == 'Agent'
    end
  end
end
