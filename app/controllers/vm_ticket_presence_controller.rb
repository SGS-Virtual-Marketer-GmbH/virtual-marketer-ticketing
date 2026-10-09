# Which colleagues have which tickets open right now, for a whole queue at once.
#
# The ticket zoom already shows this for the one ticket you are in
# (App.VmCollisionBanner, from the shared taskbar preferences). A queue lists
# dozens of tickets, and subscribing to each one's preferences would mean one
# subscription per row, so the workspace asks here once for all visible ids.
#
# GET /api/v1/vm_ticket_presence?ids=1,2,3
#   -> { presence: { "2": [{ user_id, name, editing }] } }
#
# Only the snapshot: when the queue opens, and after a websocket reconnect.
# Afterwards the changes arrive as "vm_ticket_presence" events pushed by
# Taskbar::VmPresenceBroadcast, so the client never polls.
#
# Same meaning as the banner: a taskbar row of another agent counts while its
# last_contact is younger than IDLE_WINDOW; `editing` is a draft in progress
# (reply or note typed). Only tickets the viewer may read are answered, so this
# cannot be used to learn that a ticket exists or who works on it.
#
# Zeitwerk derives the constant from the filename -- "Vm", not "VM".
class VmTicketPresenceController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  IDLE_WINDOW = Taskbar::VmPresenceBroadcast::IDLE_WINDOW
  MAX_IDS     = 100

  def show
    ids = params[:ids].to_s.split(',').map(&:to_i).select(&:positive?).uniq.first(MAX_IDS)
    return render json: { presence: {} } if ids.empty?

    readable = Ticket.where(id: ids).select { |ticket| TicketPolicy.new(current_user, ticket).show? }.map(&:id)
    keys     = readable.index_by { |id| "Ticket-#{id}" }

    rows = Taskbar
      .where(key: keys.keys)
      .where.not(user_id: current_user.id)
      .where('last_contact > ?', IDLE_WINDOW.ago)
      .includes(:user)

    grouped = rows.select { |row| keys[row.key] && row.user }.group_by { |row| [keys[row.key], row.user_id] }
    presence = Hash.new { |hash, id| hash[id] = [] }
    grouped.each do |(ticket_id, _user_id), user_rows|
      presence[ticket_id] << Taskbar::VmPresenceBroadcast.entry_for(user_rows, user_rows.first.user)
    end

    render json: { presence: presence }
  end
end
