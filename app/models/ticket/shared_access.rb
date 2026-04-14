# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Ticket::SharedAccess < ApplicationModel
  include HasDefaultModelUserRelations
  include ChecksClientNotification

  belongs_to :ticket
  belongs_to :user, class_name: 'User'

  validates :user_id, uniqueness: { scope: :ticket_id }

  after_create :notify_shared_user
  after_create :update_ticket
  after_destroy :update_ticket

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

  def update_ticket
    ticket.touch # rubocop:disable Rails/SkipsModelValidations
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

    subject = NotificationFactory::Mailer.template(
      templateInline: 'A ticket has been shared with you (#{ticket.title})',
      objects:        { ticket: ticket, recipient: user, shared_by: shared_by },
      quote:          false,
    )

    body = NotificationFactory::Mailer.template(
      templateInline: '<div>Hi #{recipient.firstname},</div><br>' \
                      '<div><b>#{shared_by.fullname}</b> has shared ticket ' \
                      '<b>(#{config.ticket_hook}#{ticket.number})</b> with you.</div><br>' \
                      '<div>You now have access to read and comment on this ticket.</div><br>' \
                      '<div>To view the ticket, click on the following link:<br>' \
                      '<a href="#{config.http_type}://#{config.fqdn}/#ticket/zoom/#{ticket.id}">' \
                      '#{config.http_type}://#{config.fqdn}/#ticket/zoom/#{ticket.id}</a></div><br>' \
                      '<div>Your #{config.product_name} Team</div>',
      objects:        { ticket: ticket, recipient: user, shared_by: shared_by },
      quote:          true,
    )

    NotificationFactory::Mailer.deliver(
      recipient:    user,
      subject:      subject,
      body:         body,
      content_type: 'text/html',
      message_id:   "<ticket_shared.#{ticket.id}.#{user.id}.#{SecureRandom.uuid}@#{Setting.get('fqdn')}>",
      references:   ticket.get_references,
    )
  end
end
