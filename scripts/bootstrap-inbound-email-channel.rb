#!/usr/bin/env ruby
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Idempotent bootstrap of the inbound redline email channel (Email::Account).
#
# WHY A RAILS RUNNER, NOT REST:
#   Zammad's REST API can only create an email channel through
#   /api/v1/channels_email_verify, which forces a live outbound-SMTP +
#   email round-trip (EmailHelper::Verify). This channel is RECEIVE-ONLY
#   (the external legal reviewer replies to redline packet emails; Zammad
#   threads the reply onto the ticket via the [Ticket#<number>] subject
#   reference), so coupling its creation to SMTP is wrong. Creating the
#   Channel record directly — the same thing Service::Channel::Email::Create
#   does — is deterministic and needs no live email test.
#
# CREATE-ONCE MODEL:
#   Like the WorkMail mailbox itself (see legal-intake-iac/scripts/
#   provision-redline-mailbox.sh), the channel is a create-once resource.
#   This script is run ONCE per environment (locally via `bin/rails runner`,
#   on staging/prod via SSM RunCommand → docker compose exec). Re-runs are
#   safe: existing channel → options are synced (update) or left (unchanged).
#   MUTABLE settings (active, group) are afterwards managed as config-as-code
#   via scripts/configure-inbound-email.ts + zammad-config/<env>/
#   zammad-email-channels.json, applied automatically on merge.
#
# INPUTS (env vars):
#   REDLINE_IMAP_USER       required  e.g. redline-inbound@legal-intake.awsapps.com
#   REDLINE_IMAP_PASSWORD   required  the WorkMail mailbox password
#   REDLINE_IMAP_HOST       optional  default imap.mail.us-east-1.awsapps.com
#   REDLINE_SMTP_HOST       optional  default smtp.mail.us-east-1.awsapps.com
#   REDLINE_CHANNEL_GROUP   optional  group name for tickets created from
#                                     unmatched mail; default: first group
#   REDLINE_CHANNEL_ACTIVE  optional  "false" to create disabled (default true)
#
# USAGE:
#   local:   bin/rails runner scripts/bootstrap-inbound-email-channel.rb
#   staging: (via SSM) docker compose exec -T zammad-railsserver \
#              rails runner /opt/zammad/scripts/bootstrap-inbound-email-channel.rb

user     = ENV["REDLINE_IMAP_USER"].to_s.strip
password = ENV["REDLINE_IMAP_PASSWORD"].to_s
imap_host = ENV.fetch("REDLINE_IMAP_HOST", "imap.mail.us-east-1.awsapps.com")
smtp_host = ENV.fetch("REDLINE_SMTP_HOST", "smtp.mail.us-east-1.awsapps.com")
active    = ENV.fetch("REDLINE_CHANNEL_ACTIVE", "true") != "false"

# Attribute writes on Zammad models require an acting user for the
# created_by_id/updated_by_id audit columns; 1 = the system user.
UserInfo.current_user_id = 1

if user.empty? || password.empty?
  abort "ERROR: REDLINE_IMAP_USER and REDLINE_IMAP_PASSWORD must be set"
end

group = if ENV["REDLINE_CHANNEL_GROUP"].to_s.strip.empty?
          Group.order(:id).first
        else
          Group.find_by!(name: ENV["REDLINE_CHANNEL_GROUP"].strip)
        end

inbound = {
  "adapter" => "imap",
  "options" => {
    "host"           => imap_host,
    "port"           => 993,
    "ssl"            => "ssl",
    "user"           => user,
    "password"       => password,
    "folder"         => "INBOX",
    "keep_on_server" => false,
  },
}

# Outbound is configured for completeness (correct WorkMail SMTP), but this
# channel is never used for sending — agent/customer notifications go through
# the Email::Notification channel.
outbound = {
  "adapter" => "smtp",
  "options" => {
    "host"     => smtp_host,
    "port"     => 465,
    "ssl"      => true,
    "user"     => user,
    "password" => password,
  },
}

existing = Channel.where(area: "Email::Account").detect do |c|
  c.options.dig("inbound", "options", "user") == user ||
    c.options.dig(:inbound, :options, :user) == user
end

if existing
  desired = { "inbound" => inbound, "outbound" => outbound }
  current = existing.options.deep_stringify_keys.slice("inbound", "outbound")
  if current == desired && existing.group_id == group.id && existing.active == active
    puts "UNCHANGED: Email::Account channel #{existing.id} for #{user} already matches"
  else
    existing.update!(options: desired, group_id: group.id, active: active)
    puts "UPDATED: Email::Account channel #{existing.id} for #{user}"
  end
  channel = existing
else
  channel = Channel.create!(
    area:         "Email::Account",
    options:      { "inbound" => inbound, "outbound" => outbound },
    group_id:     group.id,
    last_log_in:  nil,
    last_log_out: nil,
    status_in:    "ok",
    status_out:   "ok",
    active:       active,
  )
  puts "CREATED: Email::Account channel #{channel.id} for #{user} (group #{group.name}, active #{active})"
end

address = EmailAddress.find_by(email: user)
if address
  if address.channel_id == channel.id && address.active
    puts "UNCHANGED: EmailAddress #{address.id} (#{user}) already linked"
  else
    address.update!(channel_id: channel.id, active: true)
    puts "UPDATED: EmailAddress #{address.id} (#{user}) → channel #{channel.id}"
  end
else
  address = EmailAddress.create!(
    name:    "Redline Inbound",
    email:   user,
    active:  true,
    channel: channel,
  )
  puts "CREATED: EmailAddress #{address.id} (#{user}) → channel #{channel.id}"
end

puts "DONE. channel_id=#{channel.id} active=#{channel.active} group=#{group.name}"
