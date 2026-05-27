# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe HasEmailNotificationPreference do
  subject(:user) { create(:user, email: 'test@example.com') }

  describe '#shared_ticket_email_notifications_enabled?' do
    context 'when no preference has been set' do
      it 'defaults to true' do
        expect(user.shared_ticket_email_notifications_enabled?).to be true
      end
    end

    context 'when preference is explicitly true' do
      before { user.preferences[:email_notifications_enabled] = true }

      it 'returns true' do
        expect(user.shared_ticket_email_notifications_enabled?).to be true
      end
    end

    context 'when preference is explicitly false' do
      before { user.preferences[:email_notifications_enabled] = false }

      it 'returns false' do
        expect(user.shared_ticket_email_notifications_enabled?).to be false
      end
    end
  end

  describe '#email_notification_unsubscribe_token' do
    it 'returns a hex string' do
      expect(user.email_notification_unsubscribe_token).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'is stable for the same user' do
      expect(user.email_notification_unsubscribe_token).to eq(user.email_notification_unsubscribe_token)
    end

    it 'differs between users' do
      other = create(:user, email: 'other@example.com')
      expect(user.email_notification_unsubscribe_token).not_to eq(other.email_notification_unsubscribe_token)
    end
  end

  describe '#valid_email_notification_unsubscribe_token?' do
    it 'returns true for the correct token' do
      token = user.email_notification_unsubscribe_token
      expect(user.valid_email_notification_unsubscribe_token?(token)).to be true
    end

    it 'returns false for an incorrect token' do
      expect(user.valid_email_notification_unsubscribe_token?('bad_token')).to be false
    end

    it 'returns false for a nil token' do
      expect(user.valid_email_notification_unsubscribe_token?(nil)).to be false
    end
  end
end
