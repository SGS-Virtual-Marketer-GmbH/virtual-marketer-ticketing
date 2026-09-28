# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe VmMeta::Outgoing::Message::Media do
  let(:instance) { described_class.new(**params) }

  let(:page_id)      { Faker::Number.unique.number(digits: 15).to_s }
  let(:recipient_id) { Faker::Number.unique.number(digits: 16).to_s }
  let(:platform)     { 'messenger' }

  let(:options) do
    {
      page_id:,
      page_access_token: Faker::Crypto.unique.sha256,
      human_agent_tag:   false,
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

  let(:attachment) do
    instance_double(
      Store,
      content:     'binary-file-content',
      filename:    'foto.jpg',
      preferences: { 'Mime-Type' => 'image/jpeg' },
    )
  end

  let(:message_id) { "m_#{Faker::Crypto.unique.sha1}" }

  describe '#deliver' do
    context 'on Messenger, within the standard window' do
      it 'uploads the attachment via multipart and returns the sent message id' do
        expect_any_instance_of(VmMeta::Graph::Client).to receive(:post_multipart)
          .with(
            "#{page_id}/messages",
            hash_including(
              fields:       hash_including(recipient: { id: recipient_id }.to_json),
              file_content: 'binary-file-content',
              filename:     'foto.jpg',
              mime_type:    'image/jpeg',
            )
          )
          .and_return({ 'message_id' => message_id })

        expect(instance.deliver(attachment:)).to eq(id: message_id)
      end
    end

    context 'on Instagram' do
      let(:platform) { 'instagram' }

      it 'raises InstagramAttachmentError without attempting any upload' do
        expect_any_instance_of(VmMeta::Graph::Client).not_to receive(:post_multipart)

        expect { instance.deliver(attachment:) }.to raise_error(described_class::InstagramAttachmentError)
      end

      it 'the raised error is not retryable' do
        instance.deliver(attachment:)
      rescue described_class::InstagramAttachmentError => e
        expect(e.retryable?).to be false
      end
    end
  end
end
