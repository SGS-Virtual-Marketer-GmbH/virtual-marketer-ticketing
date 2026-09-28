# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Whatsapp::Outgoing::Message::Template do
  let(:instance) { described_class.new(**params) }

  let(:params) do
    {
      access_token:     Faker::Omniauth.unique.facebook[:credentials][:token],
      phone_number_id:  Faker::Number.unique.number(digits: 15),
      recipient_number: Faker::PhoneNumber.unique.cell_phone_in_e164,
    }
  end

  describe '.deliver' do
    let(:name)            { 'order_update' }
    let(:language)        { 'de' }
    let(:components_json) { [{ 'type' => 'body', 'parameters' => [{ 'type' => 'text', 'text' => 'Max' }] }] }

    before do
      allow_any_instance_of(WhatsappSdk::Api::Messages).to receive(:send_template).and_return(internal_response)
    end

    context 'with successful response' do
      let(:message_id) { "wamid.#{Faker::Crypto.unique.sha1}==" }
      let(:response)   { { id: message_id } }

      let(:internal_response) do
        Struct.new(:messages).new([Struct.new(:id).new(message_id)])
      end

      it 'returns sent message id' do
        expect(instance.deliver(name:, language:, components_json:)).to eq(response)
      end

      it 'passes name, language and components_json through to the SDK' do
        instance.deliver(name:, language:, components_json:)

        expect(instance.messages_api).to have_received(:send_template).with(
          sender_id:        params[:phone_number_id].to_i,
          recipient_number: params[:recipient_number].to_i,
          name:,
          language:,
          components_json:,
        )
      end

      it 'sends an empty array instead of nil when there are no parameters' do
        instance.deliver(name:, language:, components_json: nil)

        expect(instance.messages_api).to have_received(:send_template).with(hash_including(components_json: []))
      end
    end

    context 'with unsuccessful response' do
      before do
        exception = WhatsappSdk::Api::Responses::HttpResponseError.new(
          body:        Struct.new(:error).new({ 'message' => 'error message' }),
          http_status: 500,
        )
        allow_any_instance_of(WhatsappSdk::Api::Messages).to receive(:send_template).and_raise(exception)
      end

      let(:internal_response) { nil }

      it 'raises an error' do
        expect { instance.deliver(name:, language:, components_json:) }.to raise_error(Whatsapp::Client::CloudAPIError, 'error message')
      end
    end
  end
end
