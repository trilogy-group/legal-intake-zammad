# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Ticket::SharedAccess < ApplicationModel
  include HasDefaultModelUserRelations
  include ChecksClientNotification

  belongs_to :ticket
  belongs_to :user, class_name: 'User'

  validates :user_id, uniqueness: { scope: :ticket_id }

  after_create :notify_shared_user
  after_create :signal_ticket_change
  after_destroy :signal_ticket_change

  def self.shared_with?(ticket, user)
    exists?(ticket: ticket, user: user)
  end

  def self.share!(ticket, user, created_by:)
    find_or_create_by!(ticket: ticket, user: user) do |record|
      record.created_by = created_by
      record.updated_by = created_by
    end
  end

  def self.unshare!(ticket, user)
    find_by(ticket: ticket, user: user)&.destroy!
  end

  private

  def signal_ticket_change
    ticket.touch # rubocop:disable Rails/SkipsModelValidations

    EventBuffer.add('transaction', {
      object:     'Ticket',
      type:       'update',
      data:       ticket,
      changes:    { 'shared_access_user_ids' => [nil, ticket.shared_accesses.pluck(:user_id)] },
      id:         ticket_id,
      user_id:    created_by_id,
      created_at: Time.zone.now,
    })
  end

  def notify_shared_user
    OnlineNotification.add(
      type:          'create',
      object:        'Ticket',
      o_id:          ticket_id,
      seen:          false,
      created_by_id: created_by_id,
      user_id:       user_id,
    )
    send_share_email
  end

  def send_share_email
    return if user.email.blank?

    shared_by = User.find(created_by_id)

    result = NotificationFactory::Mailer.template(
      template:   'ticket_shared',
      locale:     user.preferences[:locale] || Locale.default,
      objects:    { ticket: ticket, recipient: user, shared_by: shared_by },
      standalone: true,
    )

    NotificationFactory::Mailer.deliver(
      recipient:    user,
      subject:      result[:subject],
      body:         result[:body],
      content_type: 'text/html',
      message_id:   "<ticket_shared.#{ticket.id}.#{user.id}.#{SecureRandom.uuid}@#{Setting.get('fqdn')}>",
      references:   ticket.get_references,
    )
  end
end
