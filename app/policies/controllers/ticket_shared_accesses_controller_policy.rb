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

  def ticket_accessible?
    TicketPolicy.new(user, ticket).show?
  end

  def can_share?
    return true if TicketPolicy.new(user, ticket).agent_read_access?

    ticket.customer_id == user.id || Ticket::SharedAccess.shared_with?(ticket, user)
  end

  def can_unshare?
    shared_access = Ticket::SharedAccess.find_by(id: record.params[:id])
    return false if !shared_access

    return true if TicketPolicy.new(user, ticket).agent_read_access?
    return true if ticket.customer_id == user.id
    return true if shared_access.user_id == user.id

    false
  end
end
