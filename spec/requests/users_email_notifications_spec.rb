# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Users email notifications', type: :request do
  let(:customer) { create(:customer, email: 'customer@example.com') }

  describe 'PUT /api/v1/users/email_notifications' do
    context 'when authenticated' do
      before { authenticated_as(customer) }

      it 'sets email_notifications_enabled to false' do
        put '/api/v1/users/email_notifications', params: { enabled: false }, as: :json
        expect(response).to have_http_status(:ok)
        expect(customer.reload.preferences[:email_notifications_enabled]).to be false
      end

      it 'sets email_notifications_enabled to true' do
        customer.preferences[:email_notifications_enabled] = false
        customer.save!

        put '/api/v1/users/email_notifications', params: { enabled: true }, as: :json
        expect(response).to have_http_status(:ok)
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

  describe 'GET /api/v1/users/unsubscribe_notifications' do
    let(:token) { customer.email_notification_unsubscribe_token }

    it 'disables email notifications with a valid token' do
      get '/api/v1/users/unsubscribe_notifications', params: { user_id: customer.id, token: token }
      expect(response).to have_http_status(:ok)
      expect(customer.reload.preferences[:email_notifications_enabled]).to be false
    end

    it 'renders an HTML confirmation page on success' do
      get '/api/v1/users/unsubscribe_notifications', params: { user_id: customer.id, token: token }
      expect(response.content_type).to include('text/html')
      expect(response.body).to include('You have been unsubscribed')
    end

    it 'renders an HTML error page for an invalid token' do
      get '/api/v1/users/unsubscribe_notifications', params: { user_id: customer.id, token: 'invalid' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.content_type).to include('text/html')
      expect(response.body).to include('Invalid or expired')
    end

    it 'returns 422 for a non-existent user_id' do
      get '/api/v1/users/unsubscribe_notifications', params: { user_id: 999_999, token: token }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not require authentication' do
      expect do
        get '/api/v1/users/unsubscribe_notifications', params: { user_id: customer.id, token: token }
      end.not_to raise_error
      expect(response).to have_http_status(:ok)
    end
  end
end
