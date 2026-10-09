# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taskbar::VmPresenceBroadcast, type: :model do
  let(:ticket)    { create(:ticket) }
  let(:agent)     { create(:agent, groups: [ticket.group]) }
  let(:colleague) { create(:agent, groups: [ticket.group]) }
  let(:outsider)  { create(:agent) }

  before do
    allow(Sessions).to receive(:send_to)
    colleague
    outsider
  end

  it 'tells colleagues with access when someone opens the ticket, but not the opener or outsiders' do
    create(:taskbar, key: "Ticket-#{ticket.id}", user_id: agent.id, callback: 'TicketZoom', params: { ticket_id: ticket.id })

    expect(Sessions).to have_received(:send_to).with(colleague.id, hash_including(event: 'vm_ticket_presence', data: hash_including(ticket_id: ticket.id, user_id: agent.id, present: true)))
    expect(Sessions).not_to have_received(:send_to).with(agent.id, anything)
    expect(Sessions).not_to have_received(:send_to).with(outsider.id, anything)
  end

  it 'says the person left when the taskbar is destroyed' do
    taskbar = create(:taskbar, key: "Ticket-#{ticket.id}", user_id: agent.id, callback: 'TicketZoom', params: { ticket_id: ticket.id })
    taskbar.destroy!

    expect(Sessions).to have_received(:send_to).with(colleague.id, hash_including(data: hash_including(present: false)))
  end

  it 'stays quiet for a heartbeat inside the revive window' do
    taskbar = create(:taskbar, key: "Ticket-#{ticket.id}", user_id: agent.id, callback: 'TicketZoom', params: { ticket_id: ticket.id })
    RSpec::Mocks.space.proxy_for(Sessions).reset
    allow(Sessions).to receive(:send_to)

    taskbar.touch_last_contact!

    expect(Sessions).not_to have_received(:send_to)
  end

  it 'ignores taskbars that are not about a ticket' do
    create(:taskbar, key: "User-#{agent.id}", user_id: agent.id, callback: 'User', params: { user_id: agent.id })

    expect(Sessions).not_to have_received(:send_to)
  end
end
