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
end
