# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Mutations::User::Current::EmailNotificationsUpdate, type: :graphql do

  let(:query) do
    <<~QUERY
      mutation userCurrentEmailNotificationsUpdate($enabled: Boolean!) {
        userCurrentEmailNotificationsUpdate(enabled: $enabled) {
          success
          errors {
            message
            field
          }
        }
      }
    QUERY
  end

  context 'when authenticated as a customer', authenticated_as: :customer do
    let(:customer) { create(:customer) }

    context 'when disabling email notifications' do
      let(:variables) { { enabled: false } }

      before { gql.execute(query, variables: variables) }

      it 'returns success' do
        expect(gql.result.data[:success]).to be true
      end

      it 'persists the preference as false' do
        expect(customer.reload.preferences[:email_notifications_enabled]).to be false
      end
    end

    context 'when enabling email notifications' do
      let(:variables) { { enabled: true } }

      before do
        customer.preferences[:email_notifications_enabled] = false
        customer.save!
        gql.execute(query, variables: variables)
      end

      it 'returns success' do
        expect(gql.result.data[:success]).to be true
      end

      it 'persists the preference as true' do
        expect(customer.reload.preferences[:email_notifications_enabled]).to be true
      end
    end
  end

  context 'when authenticated as an agent', authenticated_as: :agent do
    let(:agent)     { create(:agent) }
    let(:variables) { { enabled: false } }

    before { gql.execute(query, variables: variables) }

    it 'returns success' do
      expect(gql.result.data[:success]).to be true
    end

    it 'persists the preference for the agent' do
      expect(agent.reload.preferences[:email_notifications_enabled]).to be false
    end
  end

  context 'when unauthenticated' do
    let(:variables) { { enabled: false } }

    before { gql.execute(query, variables: variables) }

    it_behaves_like 'graphql responds with error if unauthenticated'
  end
end
