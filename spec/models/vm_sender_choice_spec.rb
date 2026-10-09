# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe VmSenderChoice do
  let(:group_address) { create(:email_address) }
  let(:group)         { create(:group, email_address: group_address) }

  describe '.usable?' do
    it 'accepts an active address on an active email channel' do
      expect(described_class.usable?(create(:email_address))).to be(true)
    end

    it 'accepts an address on a Microsoft 365 (Graph) channel' do
      channel = create(:microsoft_graph_channel)

      expect(described_class.usable?(create(:email_address, channel: channel))).to be(true)
    end

    it 'refuses nil' do
      expect(described_class.usable?(nil)).to be(false)
    end

    it 'refuses an inactive address' do
      address = create(:email_address)
      address.update_column(:active, false) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.usable?(address)).to be(false)
    end

    it 'refuses an address whose channel is inactive' do
      address = create(:email_address)
      address.channel.update!(active: false)

      expect(described_class.usable?(address.reload)).to be(false)
    end

    it 'refuses an address without a channel' do
      address = create(:email_address)
      address.update_column(:channel_id, nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.usable?(address.reload)).to be(false)
    end

    it 'refuses a channel that cannot send email' do
      address = create(:email_address)
      address.channel.update!(area: 'Telegram::Account')

      expect(described_class.usable?(address.reload)).to be(false)
    end
  end

  describe '.choices_for' do
    it 'lists only the group address when there is no other usable address' do
      group

      expect(described_class.choices_for(group)).to eq([group_address])
    end

    it 'puts the group address first and appends other usable addresses' do
      other = create(:email_address, name: 'AAA first by name')

      expect(described_class.choices_for(group)).to eq([group_address, other])
    end

    it 'leaves out addresses that are not usable' do
      broken = create(:email_address)
      broken.channel.update!(active: false)

      expect(described_class.choices_for(group)).to eq([group_address])
    end

    it 'returns the usable addresses even when the group has none of its own' do
      other = create(:email_address)
      group.update!(email_address: nil)

      expect(described_class.choices_for(group)).to include(other)
    end
  end

  describe '.resolve' do
    it 'returns the group address when nothing is requested' do
      expect(described_class.resolve(group, nil)).to eq(group_address)
      expect(described_class.resolve(group, '')).to eq(group_address)
    end

    it 'returns the group address when it is requested explicitly' do
      expect(described_class.resolve(group, group_address.id.to_s)).to eq(group_address)
    end

    it 'returns another usable address' do
      other = create(:email_address)

      expect(described_class.resolve(group, other.id)).to eq(other)
    end

    it 'refuses an address that is not usable' do
      other = create(:email_address)
      other.channel.update!(active: false)

      expect { described_class.resolve(group, other.id) }
        .to raise_error(Exceptions::UnprocessableContent, %r{Absenderadresse})
    end

    it 'refuses an id that does not exist' do
      expect { described_class.resolve(group, 0) }
        .to raise_error(Exceptions::UnprocessableContent)
    end

    it 'refuses free text such as an email address' do
      expect { described_class.resolve(group, 'attacker@example.com') }
        .to raise_error(Exceptions::UnprocessableContent)
    end
  end
end
