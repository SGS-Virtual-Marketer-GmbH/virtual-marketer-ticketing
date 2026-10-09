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
# Same meaning as the banner: a taskbar row of another agent counts while its
# last_contact is younger than IDLE_WINDOW; `editing` is a draft in progress
# (reply or note typed). Only tickets the viewer may read are answered, so this
# cannot be used to learn that a ticket exists or who works on it.
#
# Zeitwerk derives the constant from the filename -- "Vm", not "VM".
class VmTicketPresenceController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  IDLE_WINDOW = 5.minutes
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

    presence = Hash.new { |hash, key| hash[key] = {} }
    rows.each do |row|
      ticket_id = keys[row.key]
      next if ticket_id.blank? || row.user.blank?

      entry = presence[ticket_id][row.user_id] ||= { user_id: row.user_id, name: row.user.fullname, editing: false }
      entry[:editing] ||= row.state_changed?
    end

    render json: { presence: presence.transform_values(&:values) }
  end
end
