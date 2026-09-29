# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Whatsapp::Webhook::Message::Interactive, :aggregate_failures, current_user_id: 1 do
  let(:channel) { create(:whatsapp_channel) }
  let(:phone)   { Faker::PhoneNumber.cell_phone_in_e164.delete('+') }

  let(:data) do
    {
      object: 'whatsapp_business_account',
      entry:  [{
        id:      '222259550976437',
        changes: [{
          value: {
            messaging_product: 'whatsapp',
            metadata:          { display_phone_number: '15551340563', phone_number_id: channel.options[:phone_number_id] },
            contacts:          [{ profile: { name: 'Erika Mustermann' }, wa_id: phone }],
            messages:          [{ from: phone, id: 'wamid.i1', timestamp: '1707921703', type: 'interactive', interactive: }],
          },
          field: 'messages',
        }],
      }],
    }.deep_symbolize_keys
  end

  let(:article) do
    described_class.new(data:, channel:).process
    Ticket::Article.where(sender: Ticket::Article::Sender.lookup(name: 'Customer')).last
  end

  context 'with a reply button' do
    let(:interactive) { { type: 'button_reply', button_reply: { id: 'yes_1', title: 'Ja, gerne' } } }

    it 'uses the title as body and keeps the id' do
      expect(article.body).to eq('Ja, gerne')
      expect(article.preferences[:whatsapp][:interactive]).to eq({ type: 'button_reply', id: 'yes_1', title: 'Ja, gerne' })
      expect(article.preferences[:whatsapp]).not_to have_key(:context_message_id)
    end
  end

  context 'with a list entry' do
    let(:interactive) { { type: 'list_reply', list_reply: { id: 'r2', title: 'Reparatur', description: 'Handstück' } } }

    it 'shows title and description' do
      expect(article.body).to eq("Reparatur\nHandstück")
    end
  end

  context 'with a submitted flow' do
    let(:interactive) { { type: 'nfm_reply', nfm_reply: { name: 'flow', body: 'Sent', response_json: '{"flow_token":"x","termin":"Dienstag"}' } } }

    it 'lists the answers without the flow token' do
      expect(article.body).to eq("Sent\ntermin: Dienstag")
    end
  end

  context 'with a flow answer that is not JSON' do
    let(:interactive) { { type: 'nfm_reply', nfm_reply: { name: 'flow', body: 'Sent', response_json: 'kaputt' } } }

    it 'still creates the article' do
      expect(article.body).to eq('Sent')
    end
  end
end
