# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'VmWhatsappTemplates', type: :request do
  let(:ticket) { create(:whatsapp_ticket) }
  let(:agent)  { create(:agent, groups: [ticket.group]) }

  let(:approved_template) do
    {
      name:               'order_update',
      language:           'de',
      category:           'UTILITY',
      header:             nil,
      header_format:      nil,
      body:               'Hallo {{1}}, Ihre Bestellung {{2}} ist bereit.',
      footer:             'DentaTec',
      buttons:            [],
      parameter_format:   'POSITIONAL',
      placeholders:       { header: [], body: %w[1 2] },
      supported:          true,
      unsupported_reason: nil,
    }
  end

  let(:unsupported_template) do
    {
      name:               'media_header',
      language:           'de',
      category:           'MARKETING',
      header:             nil,
      header_format:      'IMAGE',
      body:               'Hallo',
      footer:             nil,
      buttons:            [],
      parameter_format:   'POSITIONAL',
      placeholders:       { header: [], body: [] },
      supported:          false,
      unsupported_reason: 'Enthält einen IMAGE-Header und wird noch nicht unterstützt.',
    }
  end

  before do
    allow_any_instance_of(Whatsapp::Account::Templates).to receive(:all).and_return([approved_template, unsupported_template])
  end

  describe '#index' do
    context 'without a session' do
      it 'refuses the request' do
        get "/api/v1/vm_whatsapp/templates?ticket_id=#{ticket.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'as an agent' do
      before { authenticated_as(agent) }

      it 'returns the normalized templates for the ticket channel' do
        get "/api/v1/vm_whatsapp/templates?ticket_id=#{ticket.id}"

        expect(response).to have_http_status(:ok)
        expect(json_response['templates'].map { |t| t['name'] }).to contain_exactly('order_update', 'media_header')
      end

      context 'when the ticket has no WhatsApp channel' do
        let(:ticket) { create(:ticket) }

        it 'returns a German error' do
          get "/api/v1/vm_whatsapp/templates?ticket_id=#{ticket.id}"

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['error']).to be_present
        end
      end

      context 'when the ticket does not exist' do
        it 'returns 404' do
          get '/api/v1/vm_whatsapp/templates?ticket_id=0'

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the agent has no access to the ticket group' do
        let(:agent) { create(:agent, groups: []) }

        it 'refuses the request' do
          get "/api/v1/vm_whatsapp/templates?ticket_id=#{ticket.id}"

          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end

  describe '#send_template' do
    let(:base_params) do
      {
        ticket_id: ticket.id,
        name:      'order_update',
        language:  'de',
        parameters: {
          header: [],
          body:   [{ value: 'Max' }, { value: '236641' }],
        },
      }
    end

    context 'without a session' do
      it 'refuses the request' do
        post '/api/v1/vm_whatsapp/templates/send', params: base_params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'as an agent' do
      before { authenticated_as(agent) }

      it 'creates a whatsapp message article with the rendered text and template preferences', :aggregate_failures do
        expect do
          post '/api/v1/vm_whatsapp/templates/send', params: base_params, as: :json
        end.to change { ticket.articles.count }.by(1)

        expect(response).to have_http_status(:created)

        article = Ticket::Article.find(json_response['article_id'])
        expect(article.type.name).to eq('whatsapp message')
        expect(article.sender.name).to eq('Agent')
        expect(article.internal).to be false
        expect(article.body).to eq("Hallo Max, Ihre Bestellung 236641 ist bereit.\n\nDentaTec")
        expect(article.preferences['vm_whatsapp_template']).to include(
          'name'     => 'order_update',
          'language' => 'de',
        )
        expect(article.preferences['vm_whatsapp_template']['components_json']).to eq(
          [
            {
              'type'       => 'body',
              'parameters' => [
                { 'type' => 'text', 'text' => 'Max' },
                { 'type' => 'text', 'text' => '236641' },
              ],
            },
          ]
        )
      end

      context 'with an unknown template name' do
        it 'returns a German error and creates no article' do
          expect do
            post '/api/v1/vm_whatsapp/templates/send', params: base_params.merge(name: 'does_not_exist'), as: :json
          end.not_to change(Ticket::Article, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['error']).to be_present
        end
      end

      context 'with an unsupported template' do
        it 'refuses without creating an article' do
          expect do
            post '/api/v1/vm_whatsapp/templates/send', params: base_params.merge(name: 'media_header'), as: :json
          end.not_to change(Ticket::Article, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['error']).to include(unsupported_template[:unsupported_reason])
        end
      end

      context 'with a missing placeholder value' do
        it 'refuses without creating an article' do
          params = base_params.merge(parameters: { header: [], body: [{ value: 'Max' }, { value: '' }] })

          expect do
            post '/api/v1/vm_whatsapp/templates/send', params:, as: :json
          end.not_to change(Ticket::Article, :count)

          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context 'with a NAMED template' do
        let(:named_template) do
          {
            name:               'named_reminder',
            language:           'de',
            category:           'UTILITY',
            header:             nil,
            header_format:      nil,
            body:               'Hallo {{customer_name}}, Auftrag {{order_number}}.',
            footer:             nil,
            buttons:            [],
            parameter_format:   'NAMED',
            placeholders:       { header: [], body: %w[customer_name order_number] },
            supported:          true,
            unsupported_reason: nil,
          }
        end

        before do
          allow_any_instance_of(Whatsapp::Account::Templates).to receive(:all).and_return([named_template])
        end

        it 'builds components_json with parameter_name and renders the body', :aggregate_failures do
          params = base_params.merge(
            name:       'named_reminder',
            parameters: {
              header: [],
              body:   [
                { name: 'customer_name', value: 'Max' },
                { name: 'order_number', value: '236641' },
              ],
            },
          )

          post '/api/v1/vm_whatsapp/templates/send', params:, as: :json

          expect(response).to have_http_status(:created)

          article = Ticket::Article.find(json_response['article_id'])
          expect(article.body).to eq('Hallo Max, Auftrag 236641.')
          expect(article.preferences['vm_whatsapp_template']['components_json']).to eq(
            [
              {
                'type'       => 'body',
                'parameters' => [
                  { 'type' => 'text', 'parameter_name' => 'customer_name', 'text' => 'Max' },
                  { 'type' => 'text', 'parameter_name' => 'order_number', 'text' => '236641' },
                ],
              },
            ]
          )
        end
      end
    end
  end
end
