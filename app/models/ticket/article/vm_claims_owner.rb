# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Whoever answers the customer takes the ticket: a public reply from a person
# to a ticket nobody owns makes that person the owner. Otherwise the ticket
# stays "niemand zugewiesen" in every list and in the customer history although
# somebody is clearly handling it (seen on a WhatsApp ticket answered by an
# agent who never set herself as owner).
#
# Only a real colleague counts: not the system user (triggers, auto replies),
# not the pipeline account, not somebody without full access to the ticket's
# group. An existing owner is never replaced, internal notes never claim, and
# neither does an import or an incoming mail.
module Ticket::Article::VmClaimsOwner
  extend ActiveSupport::Concern

  # Same accounts the team board and the daily report treat as automation.
  AUTOMATION_LOGINS = %w[info@virtual-marketer.de ai@the-platform-group.com].freeze

  included do
    after_create :vm_claim_ticket_owner
  end

  private

  def vm_claim_ticket_owner
    return true if Setting.get('import_mode')
    return true if ApplicationHandleInfo.postmaster?
    return true if internal
    return true if Ticket::Article::Sender.lookup(id: sender_id)&.name != 'Agent'
    return true if !Ticket::Article::Type.lookup(id: type_id)&.communication

    ticket = Ticket.find_by(id: ticket_id)
    return true if ticket.nil? || ticket.owner_id.to_i > 1

    author = User.find_by(id: created_by_id)
    return true if author.nil? || author.id == 1 || !author.active
    return true if AUTOMATION_LOGINS.include?(author.login)
    return true if !author.group_access?(ticket.group, 'full')

    ticket.owner_id = author.id
    ticket.save
  rescue => e
    # A failed claim must never fail the reply itself.
    Rails.logger.error "VmClaimsOwner failed for ticket #{ticket_id}: #{e.class}: #{e.message}"
    true
  end
end
