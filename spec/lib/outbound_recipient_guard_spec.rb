# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe OutboundRecipientGuard do
  around do |example|
    described_class.reset!
    example.run
    described_class.reset!
  end

  def with_allowlist(value)
    ENV[described_class::ENV_KEY] = value
    described_class.reset!
    yield
  ensure
    ENV.delete(described_class::ENV_KEY)
    described_class.reset!
  end

  context 'when unconfigured' do
    it 'permits everything, so an untouched deployment behaves like upstream' do
      expect(described_class).not_to be_active
      expect(described_class.permitted?('anyone@example.com')).to be true
      expect(described_class.blocked('anyone@example.com')).to be_empty
    end
  end

  context 'when an allowlist is configured' do
    it 'permits a listed domain and blocks anything else' do
      with_allowlist('denta-tec.com,virtual-marketer.de') do
        expect(described_class.permitted?('kunde@denta-tec.com')).to be true
        expect(described_class.permitted?('info@virtual-marketer.de')).to be true
        expect(described_class.permitted?('praxis@example.com')).to be false
      end
    end

    it 'permits subdomains of a listed domain' do
      with_allowlist('denta-tec.com') do
        expect(described_class.permitted?('kunde@mail.denta-tec.com')).to be true
      end
    end

    it 'does not let a lookalike domain through on a suffix match' do
      with_allowlist('denta-tec.com') do
        expect(described_class.permitted?('angreifer@notdenta-tec.com')).to be false
        expect(described_class.permitted?('angreifer@denta-tec.com.evil.net')).to be false
      end
    end

    it 'ignores case and a leading @ in the configured value' do
      with_allowlist('@DENTA-TEC.COM') do
        expect(described_class.permitted?('Kunde@Denta-Tec.com')).to be true
      end
    end

    it 'reads every address out of a header, including display-name form' do
      with_allowlist('denta-tec.com') do
        blocked = described_class.blocked(
          'Praxis Test <praxis@example.com>, kollege@denta-tec.com',
          'cc@another.example',
        )
        expect(blocked).to contain_exactly('praxis@example.com', 'cc@another.example')
      end
    end

    it 'treats an unparseable recipient as blocked rather than letting it through' do
      with_allowlist('denta-tec.com') do
        expect(described_class.permitted?('')).to be false
        expect(described_class.permitted?(nil)).to be false
        expect(described_class.permitted?('kein-at-zeichen')).to be false
      end
    end
  end
end
