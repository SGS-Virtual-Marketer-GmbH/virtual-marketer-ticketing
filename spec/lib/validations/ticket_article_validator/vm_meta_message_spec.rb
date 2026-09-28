# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Validations::TicketArticleValidator::VmMetaMessage do
  let(:ticket) { create(:vm_meta_ticket) }

  it 'is called when a vm_meta ticket article is created' do
    expect_any_instance_of(described_class).to receive(:validate)

    create(:ticket_article, type_name: 'messenger message', sender_name: 'Agent', ticket:, body: 'hallo')
  end

  it 'calls validations for an outgoing (Agent) article' do
    expect_any_instance_of(described_class).to receive(:validate_body)

    create(:ticket_article, type_name: 'messenger message', sender_name: 'Agent', ticket:, body: 'hallo')
  end

  it 'does not call validations for an incoming (Customer) article' do
    expect_any_instance_of(described_class).not_to receive(:validate_body)

    create(:ticket_article, type_name: 'messenger message', sender_name: 'Customer', ticket:, body: 'hallo')
  end

  describe '#validate' do
    context 'messenger message' do
      it 'allows blank body with one attachment' do
        instance = build(:ticket_article,
                         :with_prepended_attachment,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        '')

        described_class.new(instance).validate

        expect(instance.errors).to be_blank
      end

      it 'requires body when there is no attachment' do
        instance = build(:ticket_article,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        '')

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Text or attachment is required')))
        )
      end

      it 'allows a single attachment' do
        instance = build(:ticket_article,
                         :with_prepended_attachment,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:)

        described_class.new(instance).validate

        expect(instance.errors).to be_blank
      end

      it 'rejects more than one attachment' do
        instance = build(:ticket_article,
                         :with_prepended_attachment,
                         type_name:         'messenger message',
                         sender_name:       'Agent',
                         ticket:,
                         attachments_count: 2)

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Only 1 attachment allowed')))
        )
      end

      it 'rejects body over 2000 characters' do
        instance = build(:ticket_article,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'a' * 2001)

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Text is too long. Maximum length is 2000 characters.')))
        )
      end

      it 'allows body of exactly 2000 characters' do
        instance = build(:ticket_article,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'a' * 2000)

        described_class.new(instance).validate

        expect(instance.errors).to be_blank
      end
    end

    context 'instagram message' do
      it 'rejects any attachment' do
        instance = build(:ticket_article,
                         :with_prepended_attachment,
                         type_name:   'instagram message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'hallo')

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Instagram Direct does not support file attachments in outgoing messages.')))
        )
      end

      it 'rejects body over 1000 characters' do
        instance = build(:ticket_article,
                         type_name:   'instagram message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'a' * 1001)

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Text is too long. Maximum length is 1000 characters.')))
        )
      end

      it 'allows plain text within the limit' do
        instance = build(:ticket_article,
                         type_name:   'instagram message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'hallo, gerne helfen wir weiter')

        described_class.new(instance).validate

        expect(instance.errors).to be_blank
      end
    end

    context 'ticket state' do
      let(:ticket) { create(:vm_meta_ticket, state: Ticket::State.find_by(name: 'closed')) }

      it 'rejects a reply on a closed ticket' do
        instance = build(:ticket_article,
                         type_name:   'messenger message',
                         sender_name: 'Agent',
                         ticket:,
                         body:        'hallo')

        described_class.new(instance).validate

        expect(instance.errors).to have_attributes(
          errors: include(have_attributes(message: include('Reply allowed only for open tickets')))
        )
      end
    end
  end
end
