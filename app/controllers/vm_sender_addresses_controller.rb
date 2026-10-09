# The sender addresses an agent may pick when replying to a ticket by email.
#
# GET /api/v1/vm_sender_addresses?ticket_id=
#   -> { addresses: [{ id, email, name, default }] }
#
# The first entry is the group's own address (default: true), which is what a
# reply is sent from when nothing is chosen. The list is computed by
# VmSenderChoice, the same rule the server applies when the article is created.
# A group without extra addresses returns exactly one entry, and the reply box
# then shows no selector at all.
#
# Zeitwerk derives the constant from the filename -- "Vm", not "VM" (see
# VmAssistantController).
class VmSenderAddressesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def index
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :follow_up?)

    default = ticket.group.email_address

    render json: {
      addresses: VmSenderChoice.choices_for(ticket.group).map do |address|
        {
          id:      address.id,
          email:   address.email,
          name:    address.name,
          default: address.id == default&.id,
        }
      end
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: __('Ticket wurde nicht gefunden.') }, status: :not_found
  end
end
