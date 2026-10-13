# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Validations::TicketArticleValidator
  class VmMetaComment < Backend
    MATCHING_TYPES = ['facebook comment', 'instagram comment'].freeze

    # Instagram caps a comment at 2200 characters, Facebook at 8000.
    MAX_TEXT_LENGTH = {
      'facebook comment'  => 8_000,
      'instagram comment' => 2_200,
    }.freeze

    def validate_no_attachments
      return if all_attachments.blank?

      @record.errors.add :base, __('Comments cannot carry attachments.')
    end

    def validate_body
      return if @record.body.present?

      @record.errors.add :base, __('Text is required')
    end

    def validate_body_length
      return if @record.body.blank?

      max_length = MAX_TEXT_LENGTH.fetch(type_name, 2_200)
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

    def all_attachments
      @all_attachments ||= @record.attachments + (@record.instance_variable_get(:@attachments_buffer) || [])
    end

    def validator_applies?
      sender = Ticket::Article::Sender.lookup id: @record.sender_id

      sender.name == 'Agent'
    end
  end
end
