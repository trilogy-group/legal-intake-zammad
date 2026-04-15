# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::SharedAccess, type: :model do
  let(:ticket)     { create(:ticket) }
  let(:customer)   { create(:customer) }
  let(:agent)      { create(:agent) }

  describe '.share!' do
    it 'creates a shared access record' do
      expect { described_class.share!(ticket, customer, created_by: agent) }
        .to change(described_class, :count).by(1)
    end

    it 'does not duplicate when sharing the same user twice' do
      described_class.share!(ticket, customer, created_by: agent)
      expect { described_class.share!(ticket, customer, created_by: agent) }
        .not_to change(described_class, :count)
    end

    it 'creates an online notification for the shared user' do
      expect { described_class.share!(ticket, customer, created_by: agent) }
        .to change { OnlineNotification.where(user_id: customer.id).count }.by(1)
    end
  end

  describe '.unshare!' do
    before { described_class.share!(ticket, customer, created_by: agent) }

    it 'removes the shared access record' do
      expect { described_class.unshare!(ticket, customer) }
        .to change(described_class, :count).by(-1)
    end
  end

  describe '.shared_with?' do
    it 'returns false when not shared' do
      expect(described_class.shared_with?(ticket, customer)).to be false
    end

    it 'returns true when shared' do
      described_class.share!(ticket, customer, created_by: agent)
      expect(described_class.shared_with?(ticket, customer)).to be true
    end
  end

  describe 'uniqueness validation' do
    before { described_class.share!(ticket, customer, created_by: agent) }

    it 'prevents duplicate entries' do
      duplicate = described_class.new(ticket: ticket, user: customer, created_by: agent, updated_by: agent)
      expect(duplicate).not_to be_valid
    end
  end
end
