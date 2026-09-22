# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Channel::Filter::DuplicateContentCheck, type: :channel_filter do
  let(:ticket) { create(:ticket) }

  let(:base_mail) do
    {
      :'x-zammad-ticket-id' => ticket.id,
      from:                    'kunde@example.de',
      subject:                 'Frage zu meiner Bestellung',
      body:                    'Hallo, wo ist meine Bestellung 12345?',
      message_id:               '<reimport-variant@example.de>',
      date:                     Time.zone.parse('2026-09-22 08:00:00 UTC'),
    }
  end

  context 'when there is no x-zammad-ticket-id (new-ticket path)' do
    let(:mail_hash) { base_mail.except(:'x-zammad-ticket-id') }

    it 'does nothing' do
      filter(mail_hash)

      expect(mail_hash[:'x-zammad-ignore']).to be_nil
    end
  end

  context 'when an existing article has the exact same Message-ID' do
    before do
      create(:ticket_article, ticket: ticket, message_id: base_mail[:message_id], created_at: 60.days.ago)
    end

    it 'ignores the reimport regardless of age' do
      filter(base_mail)

      expect(base_mail[:'x-zammad-ignore']).to be true
    end
  end

  context 'when an existing article was stored by an Agent or marked internal (widened comparison set)' do
    let!(:agent_copy) do
      create(:ticket_article, :outbound_email, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: base_mail[:body])
    end

    it 'still catches it via Message-ID' do
      agent_copy.update_columns(message_id: base_mail[:message_id]) # rubocop:disable Rails/SkipsModelValidations

      filter(base_mail)

      expect(base_mail[:'x-zammad-ignore']).to be true
    end
  end

  context 'when content matches but the Message-ID differs (rewritten in transit)' do
    let(:mail_hash) { base_mail.merge(message_id: '<rewritten-id@example.de>') }

    context 'and the existing article carries the same stored Date' do
      before do
        create(:ticket_article, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: base_mail[:body],
                                 message_id: '<original@example.de>', preferences: { 'vm_mail_date' => base_mail[:date].to_s })
      end

      it 'ignores the reimport' do
        filter(mail_hash)

        expect(mail_hash[:'x-zammad-ignore']).to be true
      end
    end

    context 'and the existing article carries a different stored Date (genuinely different message)' do
      before do
        create(:ticket_article, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: base_mail[:body],
                                 message_id: '<original@example.de>', preferences: { 'vm_mail_date' => 3.days.ago.to_s })
      end

      it 'does NOT ignore it - a second short reply is not a reimport' do
        filter(mail_hash)

        expect(mail_hash[:'x-zammad-ignore']).to be_nil
      end
    end

    context 'and the existing article has no stored Date (predates this fix)' do
      before do
        create(:ticket_article, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: base_mail[:body],
                                 message_id: '<original@example.de>', preferences: {})
      end

      it 'still ignores it - historical backlog has no date to compare against' do
        filter(mail_hash)

        expect(mail_hash[:'x-zammad-ignore']).to be true
      end
    end
  end

  context 'when content and Message-ID both genuinely differ' do
    before do
      create(:ticket_article, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: 'A completely different question',
                               message_id: '<other@example.de>')
    end

    it 'does not ignore it' do
      filter(base_mail)

      expect(base_mail[:'x-zammad-ignore']).to be_nil
    end
  end

  context 'when the only matching article is outside the fingerprint window' do
    let(:mail_hash) { base_mail.merge(message_id: '<rewritten-id-2@example.de>') }

    before do
      create(:ticket_article, ticket: ticket, from: base_mail[:from], subject: base_mail[:subject], body: base_mail[:body],
                               message_id: '<original@example.de>', created_at: 40.days.ago)
    end

    it 'does not match via fingerprint' do
      filter(mail_hash)

      expect(mail_hash[:'x-zammad-ignore']).to be_nil
    end
  end

  describe 'tagging the mail with its Date header' do
    it 'sets vm_mail_date in x-zammad-article-preferences so future reimports can compare against it' do
      mail_hash = base_mail.dup

      filter(mail_hash)

      expect(mail_hash[:'x-zammad-article-preferences'][:vm_mail_date]).to eq(base_mail[:date].to_s)
    end

    it 'does not clobber preferences already set by an earlier filter (e.g. AutoResponseCheck)' do
      mail_hash = base_mail.merge(:'x-zammad-article-preferences' => { 'send-auto-response' => true })

      filter(mail_hash)

      expect(mail_hash[:'x-zammad-article-preferences']).to include('send-auto-response' => true, vm_mail_date: base_mail[:date].to_s)
    end
  end
end
