# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Article::EnqueueCommunicateVmMetaJob, performs_jobs: true do
  before { allow(Delayed::Job).to receive(:enqueue).and_call_original }

  let(:article) { create(:ticket_article, **(try(:factory_options) || {})) }

  shared_examples 'for no-op' do
    it 'is a no-op' do
      expect { article }.not_to have_enqueued_job(CommunicateVmMetaJob)
    end
  end

  shared_examples 'for success' do
    it 'enqueues the VmMeta background job' do
      expect { article }.to have_enqueued_job(CommunicateVmMetaJob)
    end
  end

  context 'when in Import Mode' do
    before { Setting.set('import_mode', true) }

    let(:factory_options) { { sender_name: 'Agent', type_name: 'messenger message' } }

    include_examples 'for no-op'
  end

  context 'when article is from a customer' do
    let(:factory_options) { { sender_name: 'Customer', type_name: 'messenger message' } }

    include_examples 'for no-op'
  end

  context 'when article is neither a messenger nor instagram message' do
    let(:factory_options) { { sender_name: 'Agent', type_name: 'note' } }

    include_examples 'for no-op'
  end

  context 'when article is a messenger message' do
    let(:factory_options) { { sender_name: 'Agent', type_name: 'messenger message' } }

    include_examples 'for success'
  end

  context 'when article is an instagram message' do
    let(:factory_options) { { sender_name: 'Agent', type_name: 'instagram message' } }

    include_examples 'for success'
  end
end
