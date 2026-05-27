# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Mixin that provides customer email notification preference helpers and
# HMAC-based one-click unsubscribe token generation / verification.
module HasEmailNotificationPreference
  extend ActiveSupport::Concern

  UNSUBSCRIBE_HMAC_SALT = 'email_notifications_unsubscribe'.freeze

  # Generate a signed token for the one-click unsubscribe link.
  # The token encodes user_id + email so it cannot be reused across accounts.
  def email_notification_unsubscribe_token
    payload = "#{id}:#{email}"
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base + UNSUBSCRIBE_HMAC_SALT, payload)
  end

  # Verify a token submitted to the unsubscribe endpoint.
  def valid_email_notification_unsubscribe_token?(token)
    expected = email_notification_unsubscribe_token
    ActiveSupport::SecurityUtils.secure_compare(expected, token.to_s)
  end

  # Whether the user currently has email notifications enabled.
  # Defaults to true when no preference has been stored.
  def email_notifications_enabled?
    preferences.fetch(:email_notifications_enabled, true)
  end
end
