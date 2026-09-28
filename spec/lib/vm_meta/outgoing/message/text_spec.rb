# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe VmMeta::Outgoing::Message::Text do
  let(:instance) { described_class.new(**params) }

  let(:page_id)       { Faker::Number.unique.number(digits: 15).to_s }
  let(:recipient_id)  { Faker::Number.unique.number(digits: 16).to_s }
  let(:platform)      { 'messenger' }
  let(:human_agent_tag) { false }

  let(:options) do
    {
      page_id:,
      page_access_token: Faker::Crypto.unique.sha256,
      human_agent_tag:,
    }
  end

  let(:last_customer_message_at) { Time.zone.now }

  let(:params) do
    {
      options:,
      recipient_id:,
      platform:,
      last_customer_message_at:,
    }
  end

  let(:message_id) { "m_#{Faker::Crypto.unique.sha1}" }
  let(:body)       { 'Vielen Dank fuer Ihre Nachricht, wir kuemmern uns darum.' }

  describe '#deliver' do
    context 'when the 24 hour standard window is open' do
      it 'sends messaging_type RESPONSE' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post)
          .with("#{page_id}/messages", hash_including(messaging_type: 'RESPONSE', recipient: { id: recipient_id }, message: { text: body }))
          .and_return({ 'message_id' => message_id })

        expect(instance.deliver(body:)).to eq(id: message_id)
      end
    end

    context 'when the standard window is closed but the human_agent_tag window is open and allowed' do
      let(:human_agent_tag)           { true }
      let(:last_customer_message_at)  { 3.days.ago }

      it 'sends messaging_type MESSAGE_TAG with tag HUMAN_AGENT' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post)
          .with("#{page_id}/messages", hash_including(messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT'))
          .and_return({ 'message_id' => message_id })

        instance.deliver(body:)
      end
    end

    context 'when the standard window is closed and human_agent_tag is not allowed by the channel' do
      let(:human_agent_tag)          { false }
      let(:last_customer_message_at) { 2.days.ago }

      it 'raises WindowClosedError without sending anything' do
        expect_any_instance_of(VmMeta::Graph::Client).not_to receive(:post)

        expect { instance.deliver(body:) }.to raise_error(VmMeta::Outgoing::Message::WindowClosedError)
      end
    end

    context 'when even the human_agent_tag window (7 days) has expired' do
      let(:human_agent_tag)          { true }
      let(:last_customer_message_at) { 8.days.ago }

      it 'raises WindowClosedError' do
        expect { instance.deliver(body:) }.to raise_error(VmMeta::Outgoing::Message::WindowClosedError)
      end
    end

    context 'when no customer message was ever received' do
      let(:last_customer_message_at) { nil }

      it 'raises WindowClosedError' do
        expect { instance.deliver(body:) }.to raise_error(VmMeta::Outgoing::Message::WindowClosedError)
      end
    end

    context 'for an Instagram recipient within the standard window' do
      let(:platform) { 'instagram' }

      it 'still sends messaging_type RESPONSE (text messages are supported on both platforms)' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post).and_return({ 'message_id' => message_id })

        expect(instance.deliver(body:)).to eq(id: message_id)
      end
    end
  end
end
