# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Channel::Driver::BaseEmailInbound::MessageValidator do
  describe '#already_imported?' do
    let(:article) { create(:ticket_article, message_id: '<dupe-check-999@example.com>') }
    let(:channel) { {} }

    context 'when the header uses the canonical "Message-ID" casing' do
      let(:validator) { described_class.new({ 'Message-ID' => article.message_id }) }

      it 'recognizes the already-imported article' do
        expect(validator.already_imported?(true, channel)).to be true
      end
    end

    # denta-care-agent 2026-09-22: real incident - a sender whose MTA wrote
    # "Message-Id" instead of "Message-ID" defeated this exact-key lookup
    # forever, which in turn defeated the mailbox sync watermark's safety
    # net (see Channel::Filter::DuplicateContentCheck), producing 349
    # duplicate copies of one message on ticket #4206.
    context 'when the header uses a non-canonical casing (e.g. "Message-Id")' do
      let(:validator) { described_class.new({ 'Message-Id' => article.message_id }) }

      it 'still recognizes the already-imported article' do
        expect(validator.already_imported?(true, channel)).to be true
      end
    end

    context 'when the header uses lowercase casing ("message-id")' do
      let(:validator) { described_class.new({ 'message-id' => article.message_id }) }

      it 'still recognizes the already-imported article' do
        expect(validator.already_imported?(true, channel)).to be true
      end
    end

    context 'when keep_on_server is false' do
      let(:validator) { described_class.new({ 'Message-Id' => article.message_id }) }

      it 'returns false regardless of a matching article' do
        expect(validator.already_imported?(false, channel)).to be false
      end
    end

    context 'when no article with that message id exists' do
      let(:validator) { described_class.new({ 'Message-Id' => '<never-seen@example.com>' }) }

      it 'returns false' do
        expect(validator.already_imported?(true, channel)).to be false
      end
    end

    context 'when headers is nil' do
      let(:validator) { described_class.new(nil) }

      it 'returns false' do
        expect(validator.already_imported?(true, channel)).to be false
      end
    end
  end

  describe '#verify_message?' do
    it 'matches the canonical casing' do
      expect(described_class.new({ 'X-Zammad-Verify' => 'true' }).verify_message?).to be true
    end

    it 'matches a differently-cased header key' do
      expect(described_class.new({ 'x-zammad-verify' => 'true' }).verify_message?).to be true
    end
  end

  describe '#ignore?' do
    it 'matches the canonical casing' do
      expect(described_class.new({ 'X-Zammad-Ignore' => 'true' }).ignore?).to be true
    end

    it 'matches a differently-cased header key' do
      expect(described_class.new({ 'x-zammad-Ignore' => 'true' }).ignore?).to be true
    end
  end

  describe '#fresh_verify_message?' do
    it 'matches when both verify headers use non-canonical casing' do
      headers = {
        'x-zammad-verify'      => 'true',
        'x-zammad-verify-time' => 5.minutes.ago.iso8601,
      }

      expect(described_class.new(headers).fresh_verify_message?).to be true
    end
  end
end
