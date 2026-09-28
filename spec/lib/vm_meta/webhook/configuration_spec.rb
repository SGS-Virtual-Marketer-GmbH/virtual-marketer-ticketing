# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe VmMeta::Webhook::Configuration do
  describe '#verify!' do
    let(:channel) { create(:vm_meta_channel) }

    let(:options) do
      {
        callback_url_uuid:  channel.options[:callback_url_uuid],
        'hub.mode':         'subscribe',
        'hub.challenge':    Faker::Number.unique.number(digits: 10).to_s,
        'hub.verify_token': channel.options[:verify_token],
      }
    end

    context 'when channel does not exist' do
      it 'raises NoChannelError' do
        options[:callback_url_uuid] = SecureRandom.uuid
        expect { described_class.new(options:).verify! }.to raise_error(VmMeta::Webhook::NoChannelError)
      end
    end

    context 'when no callback_url_uuid is given' do
      it 'raises NoChannelError' do
        options.delete(:callback_url_uuid)
        expect { described_class.new(options:).verify! }.to raise_error(VmMeta::Webhook::NoChannelError)
      end
    end

    context 'when the existing channel is deactivated' do
      it 'raises NoChannelError' do
        channel.update!(active: false)

        expect { described_class.new(options:).verify! }.to raise_error(VmMeta::Webhook::NoChannelError)
      end
    end

    context 'when the existing channel uses a different area' do
      it 'raises NoChannelError' do
        channel.update!(area: 'foobar')

        expect { described_class.new(options:).verify! }.to raise_error(VmMeta::Webhook::NoChannelError)
      end
    end

    context 'when hub.mode is not subscribe' do
      it 'raises VerificationError' do
        options[:'hub.mode'] = 'unsubscribe'
        expect { described_class.new(options:).verify! }.to raise_error(described_class::VerificationError)
      end
    end

    context 'when hub.challenge is missing' do
      it 'raises VerificationError' do
        options[:'hub.challenge'] = ''
        expect { described_class.new(options:).verify! }.to raise_error(described_class::VerificationError)
      end
    end

    context 'when hub.verify_token does not match' do
      it 'raises VerificationError' do
        options[:'hub.verify_token'] = 'wrong-token'
        expect { described_class.new(options:).verify! }.to raise_error(described_class::VerificationError)
      end
    end

    context 'when options are entirely blank' do
      it 'raises VerificationError' do
        expect { described_class.new(options: {}).verify! }.to raise_error(described_class::VerificationError)
      end
    end

    context 'when everything is valid' do
      it 'returns hub.challenge' do
        expect(described_class.new(options:).verify!).to eq(options[:'hub.challenge'])
      end
    end
  end
end
