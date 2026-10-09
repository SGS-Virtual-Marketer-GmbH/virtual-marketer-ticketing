# Tells the colleagues who may read a ticket that someone opened it, started
# writing in it, or left it, so the workspace queue can show a dot without
# asking. The queue still fetches one snapshot when it opens (and after a
# reconnect, see VmTicketPresenceController); from there on this event is all
# it needs.
#
# Sent only when the picture for a (ticket, user) pair actually changes:
#   - a taskbar for a ticket is created or destroyed,
#   - the draft flag flips (typing starts or stops),
#   - a taskbar that went quiet is touched again (last_contact older than
#     REVIVE_AFTER), so an entry the clients already expired comes back.
# Ordinary heartbeats inside that window send nothing.
#
# The event carries how long the user has been idle rather than a timestamp,
# so a client with a wrong clock expires the dot at the right moment.
module Taskbar::VmPresenceBroadcast
  extend ActiveSupport::Concern

  IDLE_WINDOW  = 5.minutes
  REVIVE_AFTER = 1.minute
  EVENT        = 'vm_ticket_presence'.freeze
  TICKET_KEY   = %r{\ATicket-(?<id>\d+)\z}

  included do
    after_commit :vm_broadcast_presence
  end

  # The one place that defines "has it open": rows younger than the idle window.
  # Shared with VmTicketPresenceController so both always agree.
  def self.entry_for(rows, user)
    return nil if rows.blank?

    {
      user_id:      user.id,
      name:         user.fullname,
      editing:      rows.any?(&:state_changed?),
      idle_seconds: rows.map { |row| (Time.zone.now - row.last_contact).to_i.clamp(0, IDLE_WINDOW.to_i) }.min,
    }
  end

  private

  def vm_broadcast_presence
    ticket_id = key.to_s[TICKET_KEY, :id]&.to_i
    return if ticket_id.blank?
    return if !vm_presence_changed?

    ticket = Ticket.find_by(id: ticket_id)
    return if ticket.blank? || user.blank?

    rows  = Taskbar.where(key: key, user_id: user_id).where('last_contact > ?', IDLE_WINDOW.ago).to_a
    entry = Taskbar::VmPresenceBroadcast.entry_for(rows, user)
    data  = { ticket_id: ticket_id, user_id: user_id, name: user.fullname, present: entry.present?, editing: entry&.dig(:editing) || false, idle_seconds: entry&.dig(:idle_seconds) || 0 }

    User.group_access(ticket.group_id, 'read').each do |colleague|
      next if colleague.id == user_id

      Sessions.send_to(colleague.id, { event: EVENT, data: data })
    end
  rescue => e
    # A dot is a courtesy; a failure here must never roll back or slow a save.
    Rails.logger.warn "VmPresenceBroadcast failed for #{key}: #{e.class}: #{e.message}"
  end

  def vm_presence_changed?
    return true if destroyed? || previously_new_record?
    return true if saved_change_to_attribute?('state')

    before = last_contact_before_last_save
    saved_change_to_attribute?('last_contact') && (before.blank? || before < REVIVE_AFTER.ago)
  end
end
