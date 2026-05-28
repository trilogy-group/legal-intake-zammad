# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Mixin that provides the email notification preference for customers.
#
# Semantics
# ---------
# The preference controls whether a user receives emails for tickets they did
# NOT create — i.e. tickets where they are a shared customer (added via
# Ticket::SharedAccess). Ticket creators always receive emails for their own
# tickets regardless of this preference.
#
# The preference key is :email_notifications_enabled (default: true).
# Users manage this via their account settings (desktop, mobile, or legacy UI).
module HasEmailNotificationPreference
  extend ActiveSupport::Concern

  # Whether the user wants to receive email notifications for tickets shared
  # with them (i.e. tickets they did not create). Defaults to true.
  def shared_ticket_email_notifications_enabled?
    # preferences may use symbol or string keys depending on how they were stored
    val = preferences[:email_notifications_enabled]
    val = preferences['email_notifications_enabled'] if val.nil?
    return true if val.nil?

    val
  end
end
