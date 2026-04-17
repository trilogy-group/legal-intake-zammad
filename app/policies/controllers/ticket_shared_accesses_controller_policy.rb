# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Controllers::TicketSharedAccessesControllerPolicy < Controllers::ApplicationControllerPolicy
  def index?
    # Allow admins to view shared accesses for any ticket (for API/automation purposes)
    return true if user.permissions?('admin')

    # For customers: only allow viewing their own tickets or tickets shared with them
    ticket_accessible?
  end

  def create?
    can_share?
  end

  def destroy?
    can_unshare?
  end

  def search?
    # Allow both customers and admins to search for users to share with
    customer_only? || user.permissions?('admin')
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
    # Allow admins to share any ticket (for API/automation purposes)
    return true if user.permissions?('admin')

    # For customers: only allow sharing their own tickets or tickets shared with them
    return false if !customer_only?

    ticket.customer_id == user.id || Ticket::SharedAccess.shared_with?(ticket, user)
  end

  def can_unshare?
    shared_access = Ticket::SharedAccess.find_by(id: record.params[:id])
    return false if !shared_access

    # Allow admins to unshare any ticket (for API/automation purposes)
    return true if user.permissions?('admin')

    # For customers: allow unsharing if they own the ticket or if they are the shared user
    return false if !customer_only?

    ticket = shared_access.ticket
    return true if ticket.customer_id == user.id
    return true if shared_access.user_id == user.id

    false
  end
end
