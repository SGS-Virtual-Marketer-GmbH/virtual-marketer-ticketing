# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Base for outgoing Messenger/Instagram sends. 'options' is a channel's raw
# options hash (as handed down by Channel::Driver::VmMeta#deliver, which only
# gets channel.options, not the Channel record itself - same shape as
# Channel::Driver::Whatsapp#deliver).
class VmMeta::Outgoing::Message

  STANDARD_WINDOW    = 24.hours
  HUMAN_AGENT_WINDOW  = 7.days

  attr_reader :options, :recipient_id, :platform, :last_customer_message_at

  def initialize(options:, recipient_id:, platform:, last_customer_message_at:)
    @options                   = options
    @recipient_id              = recipient_id
    @platform                  = platform
    @last_customer_message_at  = last_customer_message_at
  end

  def deliver(**)
    raise NotImplementedError
  end

  private

  def client
    @client ||= VmMeta::Graph::Client.new(access_token: options[:page_access_token])
  end

  def page_id
    options[:page_id]
  end

  def human_agent_tag_allowed?
    ActiveModel::Type::Boolean.new.cast(options[:human_agent_tag])
  end

  def within_standard_window?
    last_customer_message_at.present? && last_customer_message_at > STANDARD_WINDOW.ago
  end

  def within_human_agent_window?
    last_customer_message_at.present? && last_customer_message_at > HUMAN_AGENT_WINDOW.ago
  end

  # Returns the messaging_type (+ tag) params the Send API needs, or raises a
  # (non-retryable) WindowClosedError with a customer-facing German message
  # if no window is currently open.
  def messaging_type_params
    return { messaging_type: 'RESPONSE' } if within_standard_window?
    return { messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT' } if human_agent_tag_allowed? && within_human_agent_window?

    raise WindowClosedError, window_closed_message
  end

  def window_closed_message
    if human_agent_tag_allowed? && !within_human_agent_window?
      'Das Antwortfenster ist auch mit Human-Agent-Kennzeichnung abgelaufen (7 Tage seit der letzten Kundennachricht). Der Kunde muss erneut schreiben, bevor wieder geantwortet werden kann.'
    else
      'Das 24-Stunden-Antwortfenster ist geschlossen. Eine Antwort ist erst wieder möglich, wenn der Kunde erneut schreibt.'
    end
  end

  class WindowClosedError < StandardError
    def retryable?
      false
    end
  end
end
