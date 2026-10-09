# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'VmSenderAddresses', type: :request do
  let(:group_address) { create(:email_address) }
  let(:group)         { create(:group, email_address: group_address) }
  let(:ticket)        { create(:ticket, group: group) }
  let(:agent)         { create(:agent, groups: [group]) }

  describe 'GET /api/v1/vm_sender_addresses' do
    context 'without a session' do
      it 'refuses the request' do
        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'as an agent' do
      before { authenticated_as(agent) }

      it 'returns only the group address when there is no other usable address' do
        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(response).to have_http_status(:ok)
        expect(json_response['addresses']).to eq(
          [{ 'id' => group_address.id, 'email' => group_address.email, 'name' => group_address.name, 'default' => true }]
        )
      end

      it 'lists the group address first and marks only it as default' do
        other = create(:email_address)

        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(json_response['addresses'].map { |a| a['id'] }).to eq([group_address.id, other.id])
        expect(json_response['addresses'].map { |a| a['default'] }).to eq([true, false])
      end

      it 'does not list addresses on an inactive channel' do
        broken = create(:email_address)
        broken.channel.update!(active: false)

        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(json_response['addresses'].map { |a| a['id'] }).not_to include(broken.id)
      end

      it 'does not expose channel data' do
        create(:email_address)

        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(json_response['addresses'].flat_map(&:keys).uniq).to contain_exactly('id', 'email', 'name', 'default')
      end

      it 'returns 404 for an unknown ticket' do
        get '/api/v1/vm_sender_addresses?ticket_id=0'

        expect(response).to have_http_status(:not_found)
      end

      context 'when the agent has no access to the ticket group' do
        let(:agent) { create(:agent, groups: []) }

        it 'refuses the request' do
          get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context 'as a customer' do
      before { authenticated_as(create(:customer)) }

      it 'refuses the request' do
        get "/api/v1/vm_sender_addresses?ticket_id=#{ticket.id}"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ticket_articles with a sender choice' do
    let(:other) { create(:email_address) }
    let(:params) do
      {
        ticket_id:    ticket.id,
        type:         'email',
        sender:       'Agent',
        to:           'customer@example.com',
        subject:      'Hello',
        body:         'Text',
        content_type: 'text/plain',
        preferences:  { VmSenderChoice::PREFERENCE_KEY => other.id },
      }
    end

    before { authenticated_as(agent) }

    it 'creates the article from the chosen address' do
      post '/api/v1/ticket_articles', params: params, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response['preferences']['email_address_id']).to eq(other.id)
      expect(json_response['from']).to include(other.email)
    end

    it 'answers 422 with a German message for an unusable address' do
      other.channel.update!(active: false)

      post '/api/v1/ticket_articles', params: params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('Absenderadresse')
    end

    it 'sends from the group address without a choice' do
      post '/api/v1/ticket_articles', params: params.except(:preferences), as: :json

      expect(response).to have_http_status(:created)
      expect(json_response['preferences']['email_address_id']).to eq(group_address.id)
    end
  end
end
