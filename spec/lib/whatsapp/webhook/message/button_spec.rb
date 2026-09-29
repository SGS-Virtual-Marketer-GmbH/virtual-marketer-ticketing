# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Whatsapp::Webhook::Message::Button, :aggregate_failures, current_user_id: 1 do
  let(:channel) { create(:whatsapp_channel) }
  let(:phone)   { Faker::PhoneNumber.cell_phone_in_e164.delete('+') }

  let(:message) do
    {
      from:      phone,
      id:        'wamid.button1',
      timestamp: '1707921703',
      type:      'button',
      button:    { text: 'Keine Werbung', payload: 'OPT_OUT' },
      context:   { from: '15551340563', id: 'wamid.campaign1' },
    }
  end

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
            messages:          [message],
          },
          field: 'messages',
        }],
      }],
    }.deep_symbolize_keys
  end

  it 'turns a tapped template button into a customer article' do
    described_class.new(data:, channel:).process

    article = Ticket::Article.where(sender: Ticket::Article::Sender.lookup(name: 'Customer')).last
    expect(article).to have_attributes(body: 'Keine Werbung', content_type: 'text/plain')
    expect(article.preferences[:whatsapp]).to include(
      type:               'button',
      button:             { text: 'Keine Werbung', payload: 'OPT_OUT' },
      context_message_id: 'wamid.campaign1',
    )
  end

  context 'without a button text' do
    let(:message) { super().merge(button: { payload: 'OPT_OUT' }) }

    it 'falls back to the payload' do
      described_class.new(data:, channel:).process

      expect(Ticket::Article.where(sender: Ticket::Article::Sender.lookup(name: 'Customer')).last.body).to eq('OPT_OUT')
    end
  end

  it 'is accepted by the webhook dispatcher' do
    expect(Whatsapp::Webhook::Message.descendants.map(&:to_s)).to include('Whatsapp::Webhook::Message::Button')
  end
end
