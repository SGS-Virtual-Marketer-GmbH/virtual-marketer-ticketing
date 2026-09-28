# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe VmMeta::Webhook::Payload, :aggregate_failures, current_user_id: 1 do
  let(:channel) { create(:vm_meta_channel) }
  let(:uuid)    { channel.options[:callback_url_uuid] }

  let(:sender_id) { Faker::Number.unique.number(digits: 16).to_s }
  let(:mid)        { "m_#{Faker::Crypto.unique.sha1}" }
  let(:timestamp)  { (Time.zone.now.to_f * 1000).to_i }
  let(:text)       { 'Hallo, ich habe eine Frage zu meiner Bestellung.' }

  let(:messaging_event) do
    {
      sender:    { id: sender_id },
      recipient: { id: channel.options[:page_id] },
      timestamp: timestamp,
      message:   {
        mid:  mid,
        text: text,
      },
    }
  end

  let(:entry_id) { channel.options[:page_id] }

  let(:json) do
    {
      object: 'page',
      entry:  [
        {
          id:        entry_id,
          messaging: [messaging_event],
        },
      ],
    }.to_json
  end

  let(:signature) do
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), channel.options[:app_secret], json)
  end

  # The webhook flow always looks up the sender's display name via the Graph
  # API before creating/updating the Zammad user - stub it so specs never
  # attempt a real HTTP call (and so name resolution isn't itself under test
  # here, see lib/vm_meta/graph/profile.rb for that).
  before do
    allow_any_instance_of(VmMeta::Graph::Profile).to receive(:name).and_return('Erika Mustermann')
  end

  describe '.new (signature validation)' do
    context 'when channel does not exist' do
      let(:uuid) { SecureRandom.uuid }

      it 'raises NoChannelError' do
        expect { described_class.new(json:, uuid:, signature:) }.to raise_error(VmMeta::Webhook::NoChannelError)
      end
    end

    context 'when signature is missing' do
      let(:signature) { '' }

      it 'raises SignatureError' do
        expect { described_class.new(json:, uuid:, signature:) }.to raise_error(described_class::SignatureError)
      end
    end

    context 'when signature does not match' do
      let(:signature) { 'a' * 64 }

      it 'raises SignatureError' do
        expect { described_class.new(json:, uuid:, signature:) }.to raise_error(described_class::SignatureError)
      end
    end

    context 'when signature was computed over a different body (tampered payload)' do
      let(:signature) { OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), channel.options[:app_secret], "#{json}tampered") }

      it 'raises SignatureError' do
        expect { described_class.new(json:, uuid:, signature:) }.to raise_error(described_class::SignatureError)
      end
    end

    context 'when signature matches' do
      it 'does not raise any error' do
        expect { described_class.new(json:, uuid:, signature:) }.not_to raise_error
      end
    end
  end

  describe '#process' do
    context 'when object is unsupported' do
      let(:json) { { object: 'foobar', entry: [] }.to_json }

      it 'raises ProcessableError' do
        expect { described_class.new(json:, uuid:, signature:).process }.to raise_error(described_class::ProcessableError)
      end
    end

    context "when entry id does not match the channel's page_id" do
      let(:entry_id) { 'some-other-page-id' }

      it 'raises ProcessableError' do
        expect { described_class.new(json:, uuid:, signature:).process }.to raise_error(described_class::ProcessableError)
      end
    end

    context 'when the message is an echo of our own sent message' do
      let(:messaging_event) do
        {
          sender:    { id: channel.options[:page_id] },
          recipient: { id: sender_id },
          timestamp: timestamp,
          message:   { mid: mid, text: text, is_echo: true },
        }
      end

      it 'does not create a ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket, :count)
      end

      it 'does not create an article' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket::Article, :count)
      end
    end

    %i[delivery read reaction postback].each do |event_key|
      context "when the event is a '#{event_key}' notification" do
        let(:messaging_event) do
          {
            sender:    { id: sender_id },
            recipient: { id: channel.options[:page_id] },
            timestamp: timestamp,
            event_key => {},
          }
        end

        it 'does not create a ticket' do
          expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket, :count)
        end
      end
    end

    context 'when the message is sent by the page itself to itself (should never happen, defensive check)' do
      let(:messaging_event) do
        {
          sender:    { id: channel.options[:page_id] },
          recipient: { id: channel.options[:page_id] },
          timestamp: timestamp,
          message:   { mid: mid, text: text },
        }
      end

      it 'does not create a ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket, :count)
      end
    end

    context 'when no ticket exists yet' do
      it 'creates exactly one ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.to change(Ticket, :count).by(1)
      end

      it 'creates exactly one article' do
        expect { described_class.new(json:, uuid:, signature:).process }.to change(Ticket::Article, :count).by(1)
      end

      it 'creates a page-scoped customer login' do
        described_class.new(json:, uuid:, signature:).process

        expect(User.last.login).to eq("meta-messenger-#{channel.options[:page_id]}-#{sender_id}")
      end

      it 'stores the canonical contact_ref on the user preferences' do
        described_class.new(json:, uuid:, signature:).process

        expect(User.last.preferences).to include(vm_meta: include(contact_ref: "#{channel.options[:page_id]}:#{sender_id}"))
      end

      it 'stores vm_meta ticket preferences, including contact_ref' do
        described_class.new(json:, uuid:, signature:).process

        expect(Ticket.last.preferences).to include(
          channel_id:   channel.id,
          channel_area: channel.area,
          vm_meta:      include(
            platform:           'messenger',
            sender_id:          sender_id,
            page_id:            channel.options[:page_id],
            contact_ref:        "#{channel.options[:page_id]}:#{sender_id}",
            timestamp_incoming: timestamp,
          ),
        )
      end

      it 'sets the article type to messenger message' do
        described_class.new(json:, uuid:, signature:).process

        expect(Ticket::Article.last.type.name).to eq('messenger message')
      end

      it 'sets the article message_id to the mid' do
        described_class.new(json:, uuid:, signature:).process

        expect(Ticket::Article.last.message_id).to eq(mid)
      end
    end

    context 'when an open ticket already exists for this customer + channel' do
      let(:user) { create(:user, login: "meta-messenger-#{channel.options[:page_id]}-#{sender_id}", preferences: { vm_meta: { contact_ref: "#{channel.options[:page_id]}:#{sender_id}" } }) }

      let!(:ticket) do
        create(:ticket, customer: user, group_id: channel.group_id, state_id: Ticket::State.find_by(default_create: true).id, preferences: { channel_id: channel.id, channel_area: channel.area, vm_meta: { platform: 'messenger', sender_id:, page_id: channel.options[:page_id], contact_ref: "#{channel.options[:page_id]}:#{sender_id}", timestamp_incoming: timestamp - 1000 } })
      end

      it 'does not create a new ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket, :count)
      end

      it 'appends a follow-up article to the existing ticket' do
        described_class.new(json:, uuid:, signature:).process

        expect(ticket.reload.articles.count).to eq(1)
        expect(ticket.articles.last.message_id).to eq(mid)
      end

      it 'does not create a second user' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(User, :count)
      end
    end

    context 'when the incoming mid was already processed (redelivery)' do
      before do
        described_class.new(json:, uuid:, signature:).process
      end

      it 'does not create a duplicate article' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket::Article, :count)
      end

      it 'does not create a duplicate ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.not_to change(Ticket, :count)
      end
    end

    context 'for an Instagram Direct message' do
      let(:channel)  { create(:vm_meta_channel) }
      let(:entry_id) { channel.options[:instagram_account_id] }

      let(:json) do
        {
          object: 'instagram',
          entry:  [
            {
              id:        entry_id,
              messaging: [messaging_event],
            },
          ],
        }.to_json
      end

      it 'creates a ticket' do
        expect { described_class.new(json:, uuid:, signature:).process }.to change(Ticket, :count).by(1)
      end

      it 'uses the instagram-account-scoped login' do
        described_class.new(json:, uuid:, signature:).process

        expect(User.last.login).to eq("meta-instagram-#{channel.options[:instagram_account_id]}-#{sender_id}")
      end

      it 'stores the instagram contact_ref' do
        described_class.new(json:, uuid:, signature:).process

        expect(Ticket.last.preferences[:vm_meta]).to include(contact_ref: "#{channel.options[:instagram_account_id]}:#{sender_id}")
      end

      it 'sets the article type to instagram message' do
        described_class.new(json:, uuid:, signature:).process

        expect(Ticket::Article.last.type.name).to eq('instagram message')
      end
    end
  end
end
