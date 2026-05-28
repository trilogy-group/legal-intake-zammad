# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

# Tests for customer email notification opt-out semantics (issue #12).
#
# Key rule: ticket creators ALWAYS receive emails regardless of preference.
# Shared customers CAN opt out via their email_notifications_enabled preference.
# The preference is named "email notifications for shared tickets" in the UI.
#
RSpec.describe Transaction::Notification, 'customer email opt-out' do
  let(:group)           { create(:group) }
  let(:agent_owner)     { create(:agent, groups: [group]) }
  let(:agent_other)     { create(:agent, groups: [group]) }
  let(:customer)        { create(:customer, email: 'customer@example.com') }
  let(:shared_customer) { create(:customer, email: 'shared@example.com') }
  let(:open_state)      { Ticket::State.find_by(name: 'open') }
  let(:closed_state)    { Ticket::State.find_by(name: 'closed') }
  let(:ticket) do
    create(:ticket, group: group, customer: customer, owner: agent_owner,
                    state: open_state)
  end

  before do
    Ticket::SharedAccess.share!(ticket, shared_customer, created_by: customer)
    allow(NotificationFactory::Mailer).to receive(:deliver)
    allow(NotificationFactory::Mailer).to receive(:template).and_return({ subject: 'subj', body: 'body' })
  end

  def perform_create
    item = {
      object:    'Ticket',
      type:      'create',
      object_id: ticket.id,
      user_id:   customer.id,
      changes:   {},
    }
    described_class.new(item).perform
  end

  # ---------------------------------------------------------------------------
  # Ticket creator — always receives regardless of preference
  # ---------------------------------------------------------------------------
  describe 'ticket creator' do
    context 'with no preference set (default)' do
      it 'receives the creation email' do
        perform_create

        expect(NotificationFactory::Mailer).to have_received(:deliver)
          .with(hash_including(recipient: customer)).at_least(:once)
      end
    end

    context 'when preference is explicitly true' do
      before do
        customer.preferences[:email_notifications_enabled] = true
        customer.save!
      end

      it 'still receives the creation email' do
        perform_create

        expect(NotificationFactory::Mailer).to have_received(:deliver)
          .with(hash_including(recipient: customer)).at_least(:once)
      end
    end

    context 'when preference is explicitly false' do
      before do
        customer.preferences[:email_notifications_enabled] = false
        customer.save!
      end

      it 'still receives the creation email — ticket creator cannot opt out of own ticket' do
        perform_create

        expect(NotificationFactory::Mailer).to have_received(:deliver)
          .with(hash_including(recipient: customer)).at_least(:once)
      end

      it 'completes the notification pipeline without error' do
        expect { perform_create }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Shared customer — CAN opt out
  # ---------------------------------------------------------------------------
  describe 'shared customer opt-out' do
    context 'with no preference set (default)' do
      it 'is included in CC on creation email' do
        perform_create
        # Shared customer should be in CC (default opted in)
        expect(NotificationFactory::Mailer).to have_received(:deliver).at_least(:once)
      end
    end

    context 'when preference is false (opted out)' do
      before do
        shared_customer.preferences[:email_notifications_enabled] = false
        shared_customer.save!
      end

      it 'still sends to ticket creator when shared customer is excluded' do
        perform_create

        expect(NotificationFactory::Mailer).to have_received(:deliver)
          .with(hash_including(recipient: customer)).at_least(:once)
      end

      it 'does not deliver to opted-out shared customer' do
        perform_create

        expect(NotificationFactory::Mailer).not_to have_received(:deliver)
          .with(hash_including(recipient: shared_customer))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # No edge case when ticket creator "opts out": CC still sends to opted-in parties
  # ---------------------------------------------------------------------------
  describe 'independence of ticket creator and shared customer preferences' do
    before do
      shared_customer.preferences[:email_notifications_enabled] = false
      shared_customer.save!
    end

    it 'ticket creator receives when shared customer is opted out' do
      perform_create

      expect(NotificationFactory::Mailer).to have_received(:deliver)
        .with(hash_including(recipient: customer)).at_least(:once)
    end

    it 'opted-out shared customer does not receive' do
      perform_create

      expect(NotificationFactory::Mailer).not_to have_received(:deliver)
        .with(hash_including(recipient: shared_customer))
    end
  end

  # ---------------------------------------------------------------------------
  # Ticket visibility is unaffected
  # ---------------------------------------------------------------------------
  describe 'opted-out shared customer can still view ticket' do
    before do
      shared_customer.preferences[:email_notifications_enabled] = false
      shared_customer.save!
    end

    it 'ticket still exists (accessible via portal)' do
      perform_create
      expect(ticket.reload).to be_persisted
    end
  end
end
