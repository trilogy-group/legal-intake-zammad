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

    context 'when shared by another customer' do
      let(:ticket_owner) do
        create(:customer).tap do |c|
          c.preferences[:notification_config] = {
            matrix: {
              create: {
                criteria: { owned_by_me: true, no: false },
                channel:  { email: true, online: true }
              },
              update: {
                criteria: { owned_by_me: true, no: false },
                channel:  { email: true, online: true }
              }
            }
          }
          c.save!
        end
      end
      let(:another_customer) { create(:customer) }
      let(:owner_ticket)     { create(:ticket, customer: ticket_owner) }

      it 'notifies ticket owner when agent shares their ticket' do
        expect { described_class.share!(owner_ticket, another_customer, created_by: agent) }
          .to change { OnlineNotification.where(user_id: ticket_owner.id).count }.by(1)
      end

      it 'does not notify owner when they share themselves' do
        expect { described_class.share!(owner_ticket, another_customer, created_by: ticket_owner) }
          .not_to change { OnlineNotification.where(user_id: ticket_owner.id).count }
      end
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

  describe 'share email respects email notification preference' do
    before do
      allow(NotificationFactory::Mailer).to receive(:deliver)
      allow(NotificationFactory::Mailer).to receive(:template).and_return({ subject: 'subj', body: 'body' })
    end

    context 'when shared customer has email notifications enabled (default)' do
      it 'sends the share email' do
        described_class.share!(ticket, customer, created_by: agent)
        expect(NotificationFactory::Mailer).to have_received(:deliver).at_least(:once)
      end
    end

    context 'when shared customer has email notifications disabled' do
      before do
        customer.preferences[:email_notifications_enabled] = false
        customer.save!
      end

      it 'does not send the share email to the opted-out customer' do
        described_class.share!(ticket, customer, created_by: agent)
        expect(NotificationFactory::Mailer).not_to have_received(:deliver)
          .with(hash_including(recipient: have_attributes(id: customer.id)))
      end
    end
  end
end
