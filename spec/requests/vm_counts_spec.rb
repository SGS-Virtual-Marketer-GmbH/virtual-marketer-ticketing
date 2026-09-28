# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'VmCounts', type: :request do
  describe '#index' do
    context 'without a session' do
      it 'refuses the request' do
        get '/api/v1/vm_counts'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'as an agent with no stored preference' do
      let(:agent) { create(:agent) }

      before do
        authenticated_as(agent)
        get '/api/v1/vm_counts'
      end

      it 'defaults the "Nur meine Tickets" switch to off' do
        expect(json_response['only_mine']).to be false
      end

      it 'reports no stored switch choice yet' do
        expect(json_response['only_mine_chosen']).to be false
      end

      it 'has not seen the intro hint yet' do
        expect(json_response['intro_seen']).to be false
      end

      it 'returns one row per overview with the expected shape' do
        expect(json_response['counts']).to be_an(Array)
        json_response['counts'].each do |row|
          expect(row).to include('link', 'name', 'count', 'mine', 'unassigned')
        end
      end
    end

    # The switch used to default on for everyone without the Admin role,
    # which on real data hid nearly the whole open queue from agents who had
    # not yet self-assigned anything (2026-09-28). It must default off for
    # every role now, admins included, unless they chose otherwise themselves.
    context 'as an admin with no stored preference' do
      let(:admin) { create(:admin) }

      before do
        authenticated_as(admin)
        get '/api/v1/vm_counts'
      end

      it 'also defaults the switch to off' do
        expect(json_response['only_mine']).to be false
      end
    end

    context 'when the agent already chose "on" for the switch' do
      let(:agent) { create(:agent) }

      before do
        agent.preferences[:vm_only_mine] = true
        agent.save!
        authenticated_as(agent)
        get '/api/v1/vm_counts'
      end

      it 'keeps their own choice instead of the default' do
        expect(json_response['only_mine']).to be true
      end

      it 'reports the switch as chosen' do
        expect(json_response['only_mine_chosen']).to be true
      end

      # Having a stored switch choice at all is treated as proof the agent
      # already found and used the switch, whether or not they ever
      # dismissed the hint by clicking it.
      it 'treats a stored switch choice as having seen the intro hint too' do
        expect(json_response['intro_seen']).to be true
      end
    end

    context 'when the agent already chose "off" for the switch' do
      let(:agent) { create(:agent) }

      before do
        agent.preferences[:vm_only_mine] = false
        agent.save!
        authenticated_as(agent)
        get '/api/v1/vm_counts'
      end

      it 'keeps their own choice instead of the default' do
        expect(json_response['only_mine']).to be false
      end

      it 'reports the switch as chosen even though the value is false' do
        expect(json_response['only_mine_chosen']).to be true
      end

      it 'treats a stored (false) switch choice as having seen the intro hint too' do
        expect(json_response['intro_seen']).to be true
      end
    end

    context 'when the agent already dismissed the intro hint directly' do
      let(:agent) { create(:agent) }

      before do
        agent.preferences[:vm_intro_seen] = true
        agent.save!
        authenticated_as(agent)
        get '/api/v1/vm_counts'
      end

      it 'reports the hint as seen' do
        expect(json_response['intro_seen']).to be true
      end

      it 'does not imply a switch choice was ever made' do
        expect(json_response['only_mine_chosen']).to be false
      end
    end
  end
end
