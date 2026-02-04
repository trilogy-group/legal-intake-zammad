# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe OmniAuth::Strategies::SamlDatabase do
  describe '.destroy_saml_sessions' do
    let(:saml_uid) { 'test-user@example.com' }

    context 'when sessions with matching saml_uid exist' do
      before do
        # Create sessions with different saml_uid values
        ActiveRecord::SessionStore::Session.create!(
          session_id: SecureRandom.hex(16),
          data:       { 'saml_uid' => saml_uid, 'user_id' => 1 }
        )
        ActiveRecord::SessionStore::Session.create!(
          session_id: SecureRandom.hex(16),
          data:       { 'saml_uid' => saml_uid, 'user_id' => 1 }
        )
        ActiveRecord::SessionStore::Session.create!(
          session_id: SecureRandom.hex(16),
          data:       { 'saml_uid' => 'other-user@example.com', 'user_id' => 2 }
        )
        ActiveRecord::SessionStore::Session.create!(
          session_id: SecureRandom.hex(16),
          data:       { 'user_id' => 3 }
        )
      end

      it 'destroys only sessions with matching saml_uid' do
        expect { described_class.destroy_saml_sessions(saml_uid) }
          .to change(ActiveRecord::SessionStore::Session, :count).by(-2)
      end

      it 'preserves sessions with different saml_uid' do
        described_class.destroy_saml_sessions(saml_uid)

        remaining_uids = ActiveRecord::SessionStore::Session.all.map { |s| s.data['saml_uid'] }
        expect(remaining_uids).to contain_exactly('other-user@example.com', nil)
      end
    end

    context 'when no sessions with matching saml_uid exist' do
      before do
        ActiveRecord::SessionStore::Session.create!(
          session_id: SecureRandom.hex(16),
          data:       { 'saml_uid' => 'other-user@example.com', 'user_id' => 1 }
        )
      end

      it 'does not destroy any sessions' do
        expect { described_class.destroy_saml_sessions(saml_uid) }
          .not_to change(ActiveRecord::SessionStore::Session, :count)
      end
    end
  end
end
