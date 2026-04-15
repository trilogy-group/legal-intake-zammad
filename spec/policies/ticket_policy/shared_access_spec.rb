# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe TicketPolicy, 'shared access' do
  subject(:policy) { described_class.new(user, record) }

  let(:record)   { create(:ticket, customer: ticket_customer) }
  let(:ticket_customer) { create(:customer) }

  context 'when user has shared access to the ticket' do
    let(:user) { create(:customer) }

    before { Ticket::SharedAccess.share!(record, user, created_by: ticket_customer) }

    it { is_expected.to permit_actions(%i[show full]) }

    it 'forbids time unit and checklist fields' do
      expect(policy.show?)
        .to be_truthy
        .and(forbid_fields(%i[time_unit time_units_per_type checklist referencing_checklist_tickets]))
    end
  end

  context 'when user has shared access from a different organization' do
    let(:org1) { create(:organization) }
    let(:org2) { create(:organization) }
    let(:ticket_customer) { create(:customer, organization: org1) }
    let(:user) { create(:customer, organization: org2) }

    before { Ticket::SharedAccess.share!(record, user, created_by: ticket_customer) }

    it { is_expected.to permit_actions(%i[show full]) }
  end

  context 'when user does not have shared access' do
    let(:user) { create(:customer) }

    it { is_expected.to forbid_actions(%i[show full]) }
  end

  context 'when shared access is removed' do
    let(:user) { create(:customer) }

    before do
      Ticket::SharedAccess.share!(record, user, created_by: ticket_customer)
      Ticket::SharedAccess.unshare!(record, user)
    end

    it { is_expected.to forbid_actions(%i[show full]) }
  end
end
