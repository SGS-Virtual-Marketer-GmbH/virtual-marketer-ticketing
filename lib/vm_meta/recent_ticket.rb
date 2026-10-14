# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# A chat customer who writes again shortly after an agent closed the
# conversation must land in the same ticket, not in a new one: otherwise the
# history splits (first message and image in one closed ticket, the follow-up
# alone in another). Used by the WhatsApp and the Meta direct-message handlers.
module VmMeta::RecentTicket
  WINDOW = 24.hours

  # The most recently closed ticket of this customer on this channel, closed
  # within WINDOW. Merged and removed tickets are never reopened.
  def self.find_closed(customer_id:, channel_id:)
    closed = Ticket::State.find_by(name: 'closed')
    return if closed.nil?

    Ticket
      .where(customer_id:, state_id: closed.id)
      .where('COALESCE(close_at, updated_at) > ?', WINDOW.ago)
      .reorder(updated_at: :desc)
      .limit(20)
      .find { |ticket| ticket.preferences[:channel_id] == channel_id && !ticket.tag_list.include?('spam') }
  end

  def self.closed?(ticket)
    ticket.state&.name == 'closed'
  end

  def self.add_reopen_note(ticket)
    Ticket::Article.create!(
      ticket_id:     ticket.id,
      content_type:  'text/plain',
      body:          'Ticket wieder geöffnet: Der Kunde hat sich kurz nach dem Schließen erneut gemeldet.',
      internal:      true,
      sender:        Ticket::Article::Sender.find_by(name: 'System'),
      type:          Ticket::Article::Type.find_by(name: 'note'),
      preferences:   { vm_reopened: true },
      updated_by_id: 1,
      created_by_id: 1,
    )
  rescue => e
    Rails.logger.error "VmMeta::RecentTicket - reopen note failed: #{e.message}"
  end
end
