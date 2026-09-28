# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::Ticket::Article::Type::VmMetaMessage::Deliver do
  subject(:service_result) { described_class.execute(article_id: article.id) }

  let(:channel) { create(:vm_meta_channel) }

  let(:sender_id)         { Faker::Number.unique.number(digits: 16).to_s }
  let(:timestamp_incoming) { (Time.zone.now.to_f * 1000).to_i } # epoch MILLISECONDS, see lib/vm_meta/webhook/message.rb

  let(:ticket) do
    create(:ticket, group_id: channel.group_id, preferences: { channel_id: channel.id, channel_area: channel.area, vm_meta: { platform: 'messenger', sender_id:, page_id: channel.options[:page_id], timestamp_incoming: } })
  end

  let(:article) { create(:ticket_article, type_name: 'messenger message', sender_name: 'Agent', ticket:, body: 'Vielen Dank fuer Ihre Nachricht.', **(try(:factory_options) || {})) }

  before { article }

  let(:message_id) { "m_#{Faker::Crypto.unique.sha1}" }

  describe '#execute' do
    context 'with a valid channel and sender_id, within the 24 hour window' do
      before do
        allow_any_instance_of(VmMeta::Graph::Client).to receive(:post).and_return({ 'message_id' => message_id })
      end

      it 'delivers and stores the returned message_id' do
        expect(service_result).to have_attributes(
          message_id:  message_id,
          preferences: include(
            delivery_status:         'success',
            delivery_status_date:    be_present,
            delivery_status_message: nil,
          ),
        )
      end

      it 'sends with messaging_type RESPONSE (interprets timestamp_incoming as milliseconds)' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post)
          .with(anything, hash_including(messaging_type: 'RESPONSE'))
          .and_return({ 'message_id' => message_id })

        service_result
      end
    end

    context 'when ticket.preferences has no channel_id at all' do
      let(:ticket) { create(:ticket) }

      it 'raises a permanent delivery failure' do
        expect { service_result }.to raise_error(Service::Ticket::Article::Type::PermanentDeliveryError)
      end
    end

    context 'when the channel no longer exists' do
      before { channel.destroy! }

      it 'raises a permanent delivery failure' do
        expect { service_result }.to raise_error(Service::Ticket::Article::Type::PermanentDeliveryError)
      end
    end

    context "when ticket.preferences['vm_meta']['sender_id'] is missing" do
      let(:sender_id) { nil }

      it 'raises a permanent delivery failure mentioning the missing recipient id' do
        expect { service_result }.to raise_error(Service::Ticket::Article::Type::PermanentDeliveryError, %r{Recipient id is missing})
      end
    end

    context 'when the last customer message is outside the 24h window and the channel does not allow human_agent_tag' do
      let(:channel)             { create(:vm_meta_channel, human_agent_tag: false) }
      let(:timestamp_incoming)  { ((2.days.ago).to_f * 1000).to_i }

      it 'raises a permanent (non-retryable) delivery failure' do
        expect { service_result }.to raise_error(Service::Ticket::Article::Type::PermanentDeliveryError)
      end

      it 'does not attempt to call the Graph API' do
        expect_any_instance_of(VmMeta::Graph::Client).not_to receive(:post)

        begin
          service_result
        rescue Service::Ticket::Article::Type::PermanentDeliveryError
          # expected
        end
      end
    end

    context 'when the last customer message is outside 24h but within 7 days and the channel allows human_agent_tag' do
      let(:channel)            { create(:vm_meta_channel, human_agent_tag: true) }
      let(:timestamp_incoming) { ((3.days.ago).to_f * 1000).to_i }

      it 'sends with messaging_type MESSAGE_TAG / tag HUMAN_AGENT' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post)
          .with(anything, hash_including(messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT'))
          .and_return({ 'message_id' => message_id })

        service_result
      end
    end

    context 'for an instagram message article' do
      let(:channel) { create(:vm_meta_channel) }

      let(:ticket) do
        create(:ticket, group_id: channel.group_id, preferences: { channel_id: channel.id, channel_area: channel.area, vm_meta: { platform: 'instagram', sender_id:, page_id: channel.options[:instagram_account_id], timestamp_incoming: } })
      end

      let(:article) { create(:ticket_article, type_name: 'instagram message', sender_name: 'Agent', ticket:, body: 'Danke fuer Ihre Nachricht.') }

      before do
        allow_any_instance_of(VmMeta::Graph::Client).to receive(:post).and_return({ 'message_id' => message_id })
      end

      it 'delivers successfully for plain text' do
        expect(service_result).to have_attributes(message_id: message_id)
      end
    end
  end
end
