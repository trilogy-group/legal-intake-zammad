# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class AddEmailNotificationsPermission < ActiveRecord::Migration[6.1]
  def up
    # Create the new permission for email notification preferences
    Permission.create_if_not_exists(
      name:         'user_preferences.email_notifications',
      label:        'Email Notifications',
      description:  'Manage personal email notification preference.',
      preferences:  { prio: 1685 },
      allow_signup: true,
    )

    # Grant to Customer role so customers can manage their own email notification preference
    customer_role = Role.find_by(name: 'Customer')
    customer_role&.permission_grant('user_preferences.email_notifications')
  end

  def down
    permission = Permission.find_by(name: 'user_preferences.email_notifications')
    return if permission.nil?

    permission.destroy
  end
end
