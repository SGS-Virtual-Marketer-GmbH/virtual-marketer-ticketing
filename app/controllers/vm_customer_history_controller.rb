# Every ticket of one customer, across all areas (groups), as a timeline.
#
# Zammad's own customer lists show only tickets in groups the viewer may read.
# That hides half of a conversation when it was split across areas: the first
# message sits in Vertrieb, the follow-up in Kundenservice, and an agent in the
# second area has no way to see that the first contact happened, when, or in
# which area. So this answers for ALL tickets of the customer, but only with
# what the history needs to make sense: number, when it was created and
# closed, state, area and channel.
#
# Content and editing stay per area. A ticket the viewer may read also carries
# its id and title (so the UI can link it); for every other ticket there is no
# id, no title, no article, no owner, nothing that opens or reveals it.
#
# GET /api/v1/vm_customer_history?customer_id=123
#
# Zeitwerk derives the constant from the filename -- "Vm", not "VM".
class VmCustomerHistoryController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  MAX_TICKETS = 200

  CHANNELS = {
    'email'             => 'E-Mail',
    'phone'             => 'Telefon',
    'web'               => 'Web',
    'note'              => 'Notiz',
    'whatsapp message'  => 'WhatsApp',
    'messenger message' => 'Messenger',
    'instagram message' => 'Instagram',
    'facebook comment'  => 'Facebook-Kommentar',
    'instagram comment' => 'Instagram-Kommentar',
  }.freeze

  def show
    customer = User.find_by(id: params[:customer_id].to_i)
    return render json: { error: 'Kunde nicht gefunden.' }, status: :not_found if customer.nil?

    scope   = Ticket.where(customer_id: customer.id)
    total   = scope.count
    tickets = scope.reorder(created_at: :desc).limit(MAX_TICKETS).includes(:group, :state)
    types   = Ticket::Article::Type.pluck(:id, :name).to_h

    first_types = Ticket::Article
      .where(ticket_id: tickets.map(&:id))
      .group(:ticket_id).minimum(:id)
      .then { |first_ids| Ticket::Article.where(id: first_ids.values).pluck(:ticket_id, :type_id).to_h }

    rows = tickets.map do |ticket|
      readable = TicketPolicy.new(current_user, ticket).show?

      {
        number:     ticket.number,
        created_at: ticket.created_at,
        closed_at:  ticket.close_at,
        state:      ticket.state&.name,
        group:      ticket.group&.name,
        channel:    CHANNELS[types[first_types[ticket.id]]],
        readable:   readable,
        id:         (ticket.id if readable),
        title:      (ticket.title if readable),
      }
    end

    render json: { total: total, shown: rows.size, tickets: rows }
  end
end
