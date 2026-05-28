# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class User::Current::EmailNotificationsUpdate < BaseMutation
    description 'Update the email notification preference of the currently logged in user'

    argument :enabled, Boolean, description: 'Whether the user wants to receive email notifications'

    field :success, Boolean, null: false, description: 'Was the update successful?'

    requires_permission 'user_preferences.email_notifications'

    def resolve(enabled:)
      context.current_user.with_lock do
        context.current_user.preferences[:email_notifications_enabled] = enabled
        context.current_user.save!
      end

      { success: true }
    end

  end
end
