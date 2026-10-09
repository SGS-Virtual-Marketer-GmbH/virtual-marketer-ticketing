# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

# The sender choice (VmSenderChoice) as applied when an email article is
# created. Without a choice nothing changes: the group's address is used.
RSpec.describe Ticket::Article::AddsMetadataEmail, 'sender choice' do
  let(:group_address) { create(:email_address) }
  let(:group)         { create(:group, email_address: group_address) }
  let(:ticket)        { create(:ticket, group: group) }
  let(:agent)         { create(:agent, groups: [group]) }

  def create_email_article(preferences = {})
    create(:ticket_article,
           ticket:        ticket,
           sender_name:   'Agent',
           type_name:     'email',
           created_by_id: agent.id,
           updated_by_id: agent.id,
           preferences:   preferences)
  end

  context 'without a choice' do
    it 'sends from the group address' do
      article = create_email_article

      expect(article.preferences['email_address_id']).to eq(group_address.id)
      expect(article.from).to include(group_address.email)
    end

    it 'stores no sender choice preference' do
      expect(create_email_article.preferences).not_to have_key(VmSenderChoice::PREFERENCE_KEY)
    end
  end

  context 'with the group address chosen explicitly' do
    it 'behaves like no choice' do
      article = create_email_article(VmSenderChoice::PREFERENCE_KEY => group_address.id.to_s)

      expect(article.preferences['email_address_id']).to eq(group_address.id)
    end
  end

  context 'with another usable address chosen' do
    let(:other) { create(:email_address) }

    it 'sends from that address and through its channel' do
      article = create_email_article(VmSenderChoice::PREFERENCE_KEY => other.id.to_s)

      expect(article.preferences['email_address_id']).to eq(other.id)
      expect(article.from).to include(other.email)
      expect(article.from).not_to include(group_address.email)
      expect(EmailAddress.find(article.preferences['email_address_id']).channel).to eq(other.channel)
    end

    it 'uses the name of the chosen address with the AgentNameSystemAddressName setting' do
      Setting.set('ticket_define_email_from', 'AgentNameSystemAddressName')

      article = create_email_article(VmSenderChoice::PREFERENCE_KEY => other.id.to_s)

      expect(article.from).to include(other.name).and include(other.email)
    end

    it 'keeps the agent name with the AgentName setting' do
      Setting.set('ticket_define_email_from', 'AgentName')

      article = create_email_article(VmSenderChoice::PREFERENCE_KEY => other.id.to_s)

      expect(article.from).to include(agent.firstname).and include(other.email)
    end
  end

  context 'with an address that must not be used' do
    it 'refuses an address on an inactive channel and creates nothing' do
      other = create(:email_address)
      other.channel.update!(active: false)

      expect { create_email_article(VmSenderChoice::PREFERENCE_KEY => other.id.to_s) }
        .to raise_error(Exceptions::UnprocessableContent)
        .and not_change(Ticket::Article, :count)
    end

    it 'refuses free text' do
      expect { create_email_article(VmSenderChoice::PREFERENCE_KEY => 'attacker@example.com') }
        .to raise_error(Exceptions::UnprocessableContent)
    end
  end

  context 'when a customer creates the article' do
    it 'does not touch the sender at all' do
      article = create(:ticket_article, ticket: ticket, sender_name: 'Customer', type_name: 'email')

      expect(article.preferences).not_to have_key('email_address_id')
    end
  end
end
