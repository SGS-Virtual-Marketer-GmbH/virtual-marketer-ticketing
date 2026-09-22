# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Channel::Driver::BaseEmailInbound
  class MessageValidator
    attr_reader :headers, :size

    # @param headers [Hash] in key-value format
    # @param size [Integer] in bytes
    def initialize(headers, size = nil)
      @headers = headers
      @size    = size
    end

    # Checks if email is not too big for processing
    #
    # This method is used by IMAP and MicrosoftGraphInbound only
    # It may be possible to reuse them with POP3 too, but it needs further refactoring
    def too_large?
      max_message_size = Setting.get('postmaster_max_size').to_f
      real_message_size = size.to_f / 1024 / 1024
      if real_message_size > max_message_size
        return [real_message_size, max_message_size]
      end

      false
    end

    # Checks if a message with the given headers is a Zammad verify message
    #
    # This method is used by IMAP and MicrosoftGraphInbound only
    # It may be possible to reuse them with POP3 too, but it needs further refactoring
    def verify_message?
      header('X-Zammad-Verify') == 'true'
    end

    # Checks if a message with the given headers marked to be ignored by Zammad
    #
    # This method is used by IMAP and MicrosoftGraphInbound only
    # It may be possible to reuse them with POP3 too, but it needs further refactoring
    def ignore?
      header('X-Zammad-Ignore') == 'true'
    end

    # Checks if a message is a new Zammad verify message
    #
    # Returns false only if a verify message is less than 30 minutes old
    #
    # This method is used by IMAP and MicrosoftGraphInbound only
    # It may be possible to reuse them with POP3 too, but it needs further refactoring
    def fresh_verify_message?
      return false if !verify_message?
      return false if header('X-Zammad-Verify-Time').blank?

      begin
        verify_time = Time.zone.parse(header('X-Zammad-Verify-Time'))
      rescue => e
        Rails.logger.error e
        return false
      end

      verify_time > 30.minutes.ago
    end

    # Checks if a message is already imported in a given channel
    # This check is skipped for channels which do not keep messages on the server
    #
    # This method is used by IMAP and MicrosoftGraphInbound only
    # It may be possible to reuse them with POP3 too, but it needs further refactoring
    def already_imported?(keep_on_server, channel)
      return false if !keep_on_server

      return false if !headers

      local_message_id = header('Message-ID')
      return false if local_message_id.blank?

      local_message_id_md5 = Digest::MD5.hexdigest(local_message_id)
      article = Ticket::Article.where(message_id_md5: local_message_id_md5).reorder('created_at DESC, id DESC').limit(1).first
      return false if !article

      # verify if message is already imported via same channel, if not, import it again
      ticket = article.ticket
      return false if ticket&.preferences && ticket.preferences[:channel_id].present? && channel.present? && ticket.preferences[:channel_id] != channel[:id]

      true
    end

    private

    # denta-care-agent 2026-09-22: `headers` comes straight from the raw
    # mail's own header names (Microsoft Graph reports the sender's MTA's
    # own casing verbatim - see MicrosoftGraph#headers_to_hash), and
    # #with_indifferent_access only unifies Symbol/String, never case. An
    # exact-key `headers['Message-ID']` therefore silently misses every
    # sender whose MTA writes e.g. "Message-Id". Confirmed live: this let
    # #already_imported? return false forever for one such sender, and
    # because the mailbox sync watermark's 5-minute overlap (d0d8996/
    # 0fb46e1) relies on #already_imported? to make re-listing safe, that
    # single sender's newest message was silently reimported on every poll
    # - 349 duplicate copies of one message over ~3 hours on ticket #4206.
    def header(name)
      return nil if !headers

      key = headers.keys.find { |candidate| candidate.to_s.casecmp?(name) }
      return nil if !key

      headers[key]
    end
  end
end
