# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Controllers::TicketSharedAccessesControllerPolicy < Controllers::ApplicationControllerPolicy
  def index?
    ticket_accessible?
  end

  def create?
    can_share?
  end

  def destroy?
    can_unshare?
  end

  private

  def ticket
    @ticket ||= Ticket.find(record.params[:ticket_id])
  end

  def customer_only?
    user.permissions?('ticket.customer')
  end

  def ticket_accessible?
    customer_only? && TicketPolicy.new(user, ticket).show?
  end

  def can_share?
    return false if !customer_only?

    ticket.customer_id == user.id || Ticket::SharedAccess.shared_with?(ticket, user)
  end

  def can_unshare?
    return false if !customer_only?

    shared_access = Ticket::SharedAccess.find_by(id: record.params[:id])
    return false if !shared_access

    return true if ticket.customer_id == user.id
    return true if shared_access.user_id == user.id

    false
  end
end
