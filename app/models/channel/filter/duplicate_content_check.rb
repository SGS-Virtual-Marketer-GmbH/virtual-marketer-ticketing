# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Channel::Filter::DuplicateContentCheck

  # denta-care-agent 2026-09-22: the mailbox channel's own sync watermark
  # (see d0d8996/0fb46e1) deliberately re-lists a 5 minute overlap on every
  # poll so a message can never be silently missed. Zammad's own importer
  # dedups reimports by Message-ID (MessageValidator#already_imported?) -
  # that IS the primary defense and, as of 2026-09-22, a case-insensitive
  # one (see that class) - but a message whose Message-ID was rewritten in
  # transit (real incident: ticket #381504, 169 copies) still slips past it.
  # This is the second net: a normalized content fingerprint, scoped to the
  # ticket the message would be appended to.
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

  FINGERPRINT_WINDOW = 30.days

  # Without a Date on both sides nothing tells a reimport from a second,
  # genuinely identical reply ("Danke!"), except that a reimport follows its
  # original within the sync overlap. Such a match only counts this close.
  UNDATED_WINDOW = 2.hours

  # Upper bound on articles compared per mail: a ticket with hundreds of
  # copies (the 349-article incident) must not make every poll fingerprint all.
  FINGERPRINT_MAX_ARTICLES = 200

  def self.run(_channel, mail, _transaction_params)
    # Tag the article this mail is about to become (if any) with the mail's
    # own Date header, so a FUTURE reimport of it can be told apart from a
    # second, genuinely different reply that happens to look identical (see
    # #duplicate_by_fingerprint) - a second real message from the same
    # sender essentially never carries the exact same Date.
    if mail[:date].present?
      mail[:'x-zammad-article-preferences'] ||= {}
      mail[:'x-zammad-article-preferences'][:vm_mail_date] = mail[:date].to_s
    end

    ticket_id = mail[:'x-zammad-ticket-id']
    return if ticket_id.blank?

    message_id = mail[:message_id].presence
    duplicate  = message_id.present? && duplicate_by_message_id(ticket_id, message_id)
    duplicate ||= duplicate_by_fingerprint(ticket_id, mail)
    return if !duplicate

    mail[:'x-zammad-ignore'] = true
    Rails.logger.info "DuplicateContentCheck: ignored reimport of article ##{duplicate.id} on ticket #{ticket_id} (message_id: #{message_id}, from: #{mail[:from]}, subject: #{mail[:subject]})"
  rescue => e
    Rails.logger.error "DuplicateContentCheck failed, letting the email through unmodified: #{e.inspect}"
  end

  # No time window and no sender/internal restriction: an exact Message-ID
  # match is definitive regardless of who Zammad classified the article as
  # (an agent replying from their own mail client is stored as sender Agent;
  # an article flipped to internal in the UI is still the same reimport) or
  # how long ago it landed - a resync bigger than any fixed window is
  # exactly the case where this needs to still catch it.
  def self.duplicate_by_message_id(ticket_id, message_id)
    ticket_articles(ticket_id).find_by(message_id: message_id)
  end

  # Content-fingerprint match, windowed (unlike Message-ID above, this has
  # no index to lean on) and guarded by the stored Date header where one is
  # available, so two short, genuinely-different messages with boilerplate
  # text ("Danke!", an auto-responder body) don't collide. Older articles
  # predating the vm_mail_date preference have none stored: those only match
  # within UNDATED_WINDOW, i.e. a reimport right behind its original.
  def self.duplicate_by_fingerprint(ticket_id, mail)
    fingerprint = content_fingerprint(mail[:from], mail[:subject], mail[:body])
    mail_date   = mail[:date].presence&.to_s

    ticket_articles(ticket_id)
      .where('created_at > ?', FINGERPRINT_WINDOW.ago)
      .order(id: :desc)
      .limit(FINGERPRINT_MAX_ARTICLES)
      .find do |article|
        next false if content_fingerprint(article.from, article.subject, article.body) != fingerprint

        stored_date = article.preferences['vm_mail_date']
        if stored_date.present? && mail_date.present?
          stored_date == mail_date
        else
          article.created_at > UNDATED_WINDOW.ago
        end
      end
  end

  def self.ticket_articles(ticket_id)
    Ticket::Article.where(ticket_id: ticket_id, type_id: email_type_id)
  end

  def self.email_type_id
    @email_type_id ||= Ticket::Article::Type.find_by(name: 'email')&.id
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
