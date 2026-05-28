# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Users email notifications', type: :request do
  let(:customer) { create(:customer, email: 'customer@example.com') }

  describe 'PUT /api/v1/users/email_notifications' do
    context 'when authenticated' do
      before { authenticated_as(customer) }

      it 'returns 200' do
        put '/api/v1/users/email_notifications', params: { enabled: false }, as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'sets email_notifications_enabled to false' do
        put '/api/v1/users/email_notifications', params: { enabled: false }, as: :json
        expect(customer.reload.preferences[:email_notifications_enabled]).to be false
      end

      it 'sets email_notifications_enabled to true' do
        customer.preferences[:email_notifications_enabled] = false
        customer.save!
        put '/api/v1/users/email_notifications', params: { enabled: true }, as: :json
        expect(customer.reload.preferences[:email_notifications_enabled]).to be true
      end

      it 'returns 422 when enabled param is missing' do
        put '/api/v1/users/email_notifications', params: {}, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when not authenticated' do
      it 'returns 403' do
        put '/api/v1/users/email_notifications', params: { enabled: false }, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
