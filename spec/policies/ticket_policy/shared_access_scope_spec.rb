# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe TicketPolicy::ReadScope, 'shared access' do
  subject(:scope) { described_class.new(user) }

  let(:user)            { create(:customer) }
  let(:own_ticket)      { create(:ticket, customer: user) }
  let(:other_ticket)    { create(:ticket) }
  let(:shared_ticket)   { create(:ticket) }

  before do
    own_ticket
    other_ticket
    Ticket::SharedAccess.share!(shared_ticket, user, created_by: shared_ticket.customer)
  end

  it 'includes tickets shared with the customer' do
    expect(scope.resolve).to include(shared_ticket)
  end

  it 'includes the customer own tickets' do
    expect(scope.resolve).to include(own_ticket)
  end

  it 'excludes tickets not shared and not owned' do
    expect(scope.resolve).not_to include(other_ticket)
  end

  context 'when shared access is removed' do
    before { Ticket::SharedAccess.unshare!(shared_ticket, user) }

    it 'no longer includes the previously shared ticket' do
      expect(scope.resolve).not_to include(shared_ticket)
    end
  end
end
