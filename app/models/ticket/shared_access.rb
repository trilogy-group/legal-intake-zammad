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
  end
end
