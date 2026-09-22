# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Channel::Filter::DuplicateContentCheck

  # denta-care-agent 2026-09-22: the mailbox channel's own sync watermark
  # (see d0d8996/0fb46e1) deliberately re-lists a 5 minute overlap on every
  # poll so a message can never be silently missed - but Zammad's importer
  # itself has no Message-ID dedup, so a message caught in that overlap (or
  # a larger one-off resync) becomes a second, third, ... copy appended to
  # the ticket it already landed on. Real incident: ticket #381504 collected
  # 169 copies of one reply this way, all with the SAME visible content but
  # not always the SAME Message-ID (some had been rewritten in transit),
  # which is why this also falls back to a normalized content fingerprint.
  #
  # Runs after FollowUpCheck/FollowUpMerged/FollowUpAssignment (name prefix
  # '0012', those are '0007'/'0008'/'0010') so mail[:'x-zammad-ticket-id'] is
  # already resolved - it only ever acts on a message that would be appended
  # to an ALREADY-EXISTING ticket. A brand new ticket has its own, separate,
  # already-working dedup in denta-care-agent's own webhook pipeline (a real
  # Zammad ticket merge on a Message-ID/fingerprint match), so this
  # deliberately does not touch the no-ticket-id path at all.
  #
  # Any error in here must never block a real customer email - fails open.

  WINDOW = 7.days

  def self.run(_channel, mail, _transaction_params)
    ticket_id = mail[:'x-zammad-ticket-id']
    return if ticket_id.blank?

    message_id  = mail[:message_id].presence
    fingerprint = content_fingerprint(mail[:from], mail[:subject], mail[:body])

    duplicate = existing_articles(ticket_id).find do |article|
      (message_id.present? && article.message_id == message_id) ||
        content_fingerprint(article.from, article.subject, article.body) == fingerprint
    end
    return if !duplicate

    mail[:'x-zammad-ignore'] = true
    Rails.logger.info "DuplicateContentCheck: ignored reimport of article ##{duplicate.id} on ticket #{ticket_id} (message_id: #{message_id}, from: #{mail[:from]}, subject: #{mail[:subject]})"
  rescue => e
    Rails.logger.error "DuplicateContentCheck failed, letting the email through unmodified: #{e.inspect}"
  end

  def self.existing_articles(ticket_id)
    Ticket::Article.where(
      ticket_id: ticket_id,
      type_id:   email_type_id,
      sender_id: customer_sender_id,
      internal:  false,
    ).where('created_at > ?', WINDOW.ago)
  end

  def self.email_type_id
    @email_type_id ||= Ticket::Article::Type.find_by(name: 'email')&.id
  end

  def self.customer_sender_id
    @customer_sender_id ||= Ticket::Article::Sender.find_by(name: 'Customer')&.id
  end

  def self.content_fingerprint(from, subject, body)
    normalized = [from, subject, body].map { |value| normalize(value) }.join('|')
    Digest::SHA256.hexdigest(normalized)
  end

  def self.normalize(text)
    text.to_s
      .gsub(%r{<[^>]*>}, ' ')
      .gsub(/&nbsp;/i, ' ')
      .gsub(/\s+/, ' ')
      .strip
      .downcase
  end
end
