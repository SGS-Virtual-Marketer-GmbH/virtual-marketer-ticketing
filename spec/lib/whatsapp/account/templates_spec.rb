# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Whatsapp::Account::Templates do
  subject(:templates) { described_class.new(access_token: 'token123', business_id: '998877') }

  # WhatsappSdk::Resource::Template isn't verified against the real gem
  # locally (no bundler in this environment, see the class comment in
  # lib/whatsapp/account/templates.rb) -- a plain struct with the attributes
  # the task confirmed (id, status, category, language, name,
  # components_json) stands in for it, the same way spec/services/.../
  # deliver_spec.rb mocks WhatsApp SDK responses with plain Structs rather
  # than instance_double.
  TemplateDouble = Struct.new(:id, :status, :category, :language, :name, :components_json, keyword_init: true)
  PageDouble     = Struct.new(:records, :after, keyword_init: true)

  def stub_list(*pages)
    call_count = 0
    allow_any_instance_of(WhatsappSdk::Api::Templates).to receive(:list) do
      page = pages[call_count]
      call_count += 1
      page
    end
  end

  describe '#all' do
    it 'only returns APPROVED templates' do
      approved = TemplateDouble.new(id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'order_update',
                                     components_json: [{ 'type' => 'BODY', 'text' => 'Hallo {{1}}' }])
      pending  = TemplateDouble.new(id: 2, status: 'PENDING', category: 'UTILITY', language: 'de', name: 'not_ready',
                                     components_json: [{ 'type' => 'BODY', 'text' => 'Hallo' }])

      stub_list(PageDouble.new(records: [approved, pending], after: nil))

      expect(templates.all.map { |t| t[:name] }).to eq(['order_update'])
    end

    it 'asks Meta for a single page (whatsapp_sdk 1.1.0 has no cursor)' do
      template = TemplateDouble.new(id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'only',
                                    components_json: [{ 'type' => 'BODY', 'text' => 'Hallo' }])
      stub_list(PageDouble.new(records: [template], after: 'ignored'))

      expect(templates.all.map { |t| t[:name] }).to eq(['only'])
    end

    it 'normalizes header/body/footer text and positional placeholders' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'MARKETING', language: 'de', name: 'reminder',
        components_json: [
          { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Erinnerung' },
          { 'type' => 'BODY', 'text' => 'Hallo {{1}}, Ihre Bestellung {{2}} ist bereit.' },
          { 'type' => 'FOOTER', 'text' => 'DentaTec' },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      result = templates.all.first

      expect(result).to include(
        name:             'reminder',
        language:         'de',
        category:         'MARKETING',
        header:           'Erinnerung',
        header_format:    'TEXT',
        body:             'Hallo {{1}}, Ihre Bestellung {{2}} ist bereit.',
        footer:           'DentaTec',
        parameter_format: 'POSITIONAL',
        supported:        true,
      )
      expect(result[:placeholders]).to eq(header: [], body: %w[1 2])
    end

    it 'detects a NAMED template from its placeholder names' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'named_template',
        components_json: [{ 'type' => 'BODY', 'text' => 'Hallo {{customer_name}}, Auftrag {{order_number}}.' }]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      result = templates.all.first

      expect(result[:parameter_format]).to eq('NAMED')
      expect(result[:placeholders][:body]).to eq(%w[customer_name order_number])
    end

    it 'collects button text only' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'with_buttons',
        components_json: [
          { 'type' => 'BODY', 'text' => 'Hallo' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ja' }, { 'type' => 'QUICK_REPLY', 'text' => 'Nein' }] },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      expect(templates.all.first[:buttons]).to eq(%w[Ja Nein])
    end

    %w[IMAGE VIDEO DOCUMENT LOCATION].each do |format|
      it "marks a #{format} header template as unsupported" do
        template = TemplateDouble.new(
          id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'media_header',
          components_json: [
            { 'type' => 'HEADER', 'format' => format },
            { 'type' => 'BODY', 'text' => 'Hallo' },
          ]
        )
        stub_list(PageDouble.new(records: [template], after: nil))

        result = templates.all.first

        expect(result[:supported]).to be false
        expect(result[:unsupported_reason]).to be_present
      end
    end

    it 'marks a template with an OTP button as unsupported' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'AUTHENTICATION', language: 'de', name: 'otp',
        components_json: [
          { 'type' => 'BODY', 'text' => 'Ihr Code lautet {{1}}' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP' }] },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      expect(templates.all.first[:supported]).to be false
    end

    it 'marks a template with a dynamic URL button as unsupported' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'dynamic_url',
        components_json: [
          { 'type' => 'BODY', 'text' => 'Hallo' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ansehen', 'url' => 'https://example.com/{{1}}' }] },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      expect(templates.all.first[:supported]).to be false
    end

    it 'keeps a static URL button as supported' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'UTILITY', language: 'de', name: 'static_url',
        components_json: [
          { 'type' => 'BODY', 'text' => 'Hallo' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ansehen', 'url' => 'https://example.com/status' }] },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      expect(templates.all.first[:supported]).to be true
    end

    it 'marks a carousel template as unsupported' do
      template = TemplateDouble.new(
        id: 1, status: 'APPROVED', category: 'MARKETING', language: 'de', name: 'carousel',
        components_json: [
          { 'type' => 'BODY', 'text' => 'Hallo' },
          { 'type' => 'CAROUSEL', 'cards' => [] },
        ]
      )
      stub_list(PageDouble.new(records: [template], after: nil))

      expect(templates.all.first[:supported]).to be false
    end

    it 'raises ArgumentError from initialize when business_id is missing' do
      expect { described_class.new(access_token: 'token123', business_id: nil) }.to raise_error(ArgumentError)
    end

    it 'raises a CloudAPIError when the SDK call fails' do
      exception = WhatsappSdk::Api::Responses::HttpResponseError.new(
        body:        Struct.new(:error).new({ 'message' => 'error message' }),
        http_status: 500,
      )
      allow_any_instance_of(WhatsappSdk::Api::Templates).to receive(:list).and_raise(exception)

      expect { templates.all }.to raise_error(Whatsapp::Client::CloudAPIError, 'error message')
    end
  end
end
