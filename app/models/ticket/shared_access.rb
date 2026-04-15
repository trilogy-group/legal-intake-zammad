# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Ticket::SharedAccess < ApplicationModel
  include HasDefaultModelUserRelations
  include ChecksClientNotification

  belongs_to :ticket
  belongs_to :user, class_name: 'User', inverse_of: :ticket_shared_accesses

  validates :user_id, uniqueness: { scope: :ticket_id }
  validate :user_must_be_customer
  validate :user_must_be_active
  validate :cannot_share_with_ticket_owner

  after_create :notify_shared_user
  after_create :signal_ticket_change
  after_destroy :signal_ticket_change

  def self.shared_with?(ticket, user)
    exists?(ticket: ticket, user: user)
  end

  # Share a ticket with another customer user, granting them read and comment access.
  # Creates or returns existing shared access record.
  # Sends notification email and online notification to the shared user.
  # @param ticket [Ticket] the ticket to share
  # @param user [User] the customer user to share with
  # @param created_by [User] the user performing the share action
  # @return [Ticket::SharedAccess]
  def self.share!(ticket, user, created_by:)
    find_or_create_by!(ticket: ticket, user: user) do |record|
      record.created_by = created_by
      record.updated_by = created_by
    end
  end

  # Remove shared access from a ticket for a specific user.
  # @param ticket [Ticket] the ticket to unshare
  # @param user [User] the user to remove access from
  def self.unshare!(ticket, user)
    find_by(ticket: ticket, user: user)&.destroy!
  end

  private

  # Validate that the user being shared with has customer permissions.
  # This ensures tickets can only be shared with portal customers, not agents or admins.
  def user_must_be_customer
    return if user.blank?
    return if user.permissions?('ticket.customer')

    errors.add(:user, __('must have customer permissions'))
  end

  # Validate that the user being shared with is active.
  # Inactive users should not receive new shared access.
  def user_must_be_active
    return if user.blank?
    return if user.active?

    errors.add(:user, __('must be active'))
  end

  # Validate that the ticket is not being shared with its owner.
  # Ticket owners already have full access and should not be in the shared_accesses table.
  def cannot_share_with_ticket_owner
    return if ticket.blank? || user.blank?
    return if ticket.customer_id != user_id

    errors.add(:user, __('cannot share ticket with its owner'))
  end

  # Signal to the transaction system that this ticket has changed.
  # This triggers selector updates and scheduled job evaluation.
  # We inject a synthetic 'shared_access_user_ids' change to allow
  # triggers and schedulers to react to sharing events.
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
