# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Article::AddsMetadataVmMeta do
  let(:agent)      { create(:agent) }
  let(:channel)    { create(:vm_meta_channel) }
  let(:contact_ref) { "#{channel.options[:page_id]}:#{Faker::Number.unique.number(digits: 16)}" }

  let(:ticket) do
    create(:ticket, group_id: channel.group_id, preferences: { channel_id: channel.id, channel_area: channel.area, vm_meta: { platform: 'messenger', contact_ref: } })
  end

  context 'when an agent creates a messenger reply article' do
    subject(:article) { create(:ticket_article, sender_name: 'Agent', type_name: 'messenger message', ticket:, created_by_id: agent.id, updated_by_id: agent.id) }

    it 'sets from to the agent name via the channel name' do
      expect(article.from).to eq("#{agent.firstname} #{agent.lastname} via #{channel.options[:name]}")
    end

    it 'sets to to the canonical contact_ref' do
      expect(article.to).to eq(contact_ref)
    end

    context 'when created by the system user' do
      let(:agent) { User.lookup(id: 1) }

      it 'sets from to just the channel name, without a "via" prefix' do
        expect(article.from).to eq(channel.options[:name])
      end
    end
  end

  context 'when an agent creates an instagram reply article' do
    let(:ticket) do
      create(:ticket, group_id: channel.group_id, preferences: { channel_id: channel.id, channel_area: channel.area, vm_meta: { platform: 'instagram', contact_ref: } })
    end

    subject(:article) { create(:ticket_article, sender_name: 'Agent', type_name: 'instagram message', ticket:, created_by_id: agent.id, updated_by_id: agent.id) }

    context 'when the channel has no custom display name configured' do
      let(:channel) { create(:vm_meta_channel, name: nil) }

      it 'falls back to the platform label' do
        expect(article.from).to eq("#{agent.firstname} #{agent.lastname} via Instagram")
      end
    end
  end
end
