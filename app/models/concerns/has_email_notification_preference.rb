# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Mixin that provides customer email notification preference helpers and
# HMAC-based one-click unsubscribe token generation / verification.
#
# Semantics of the preference
# ----------------------------
# The preference controls whether a user receives emails for tickets they did
# NOT create — i.e. tickets where they are a shared customer (added via
# Ticket::SharedAccess). Ticket creators always receive emails for their own
# tickets regardless of this preference. This avoids the edge case where the
# primary recipient opts out and CC'd participants also stop receiving email.
#
# The preference key is :email_notifications_enabled (default: true).
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

  # Whether the user wants to receive email notifications for tickets shared
  # with them (i.e. tickets they did not create). Defaults to true.
  def shared_ticket_email_notifications_enabled?
    preferences.fetch(:email_notifications_enabled, true)
  end
end
