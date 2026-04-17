# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketSharedAccessesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # GET /api/v1/ticket_shared_accesses?ticket_id=123
  def index
    list = ticket.shared_accesses.includes(:user)

    assets = {}
    list.each { |shared_access| assets = shared_access.user.assets(assets) }

    render json: {
      shared_accesses: list,
      assets:          assets,
    }
  end

  # POST /api/v1/ticket_shared_accesses
  def create
    raise Exceptions::UnprocessableEntity, __('You cannot share a ticket with yourself.') if target_user.id == current_user.id
    raise Exceptions::UnprocessableEntity, __('Ticket can only be shared with customer users.') if !target_user.permissions?('ticket.customer')
    raise Exceptions::UnprocessableEntity, __('Inactive users cannot be shared on tickets.') if !target_user.active?

    Ticket::SharedAccess.share!(ticket, target_user, created_by: current_user)

    render json: true, status: :created
  rescue ActiveRecord::RecordNotUnique
    render json: { error: __('This user is already shared on this ticket.') }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: __('Ticket or user not found.') }, status: :not_found
  end

  # DELETE /api/v1/ticket_shared_accesses/:id
  def destroy
    if current_user.permissions?('admin')
      # Admins can remove any shared access (for API/automation purposes)
      shared_access = Ticket::SharedAccess.find(params[:id])
    else
      # Customers can only remove shared accesses for tickets they own or have access to
      accessible_ticket_ids = Ticket.left_joins(:shared_accesses)
                                    .where('tickets.customer_id = :user_id OR ticket_shared_accesses.user_id = :user_id', user_id: current_user.id)
                                    .distinct
                                    .pluck(:id)
      shared_access = Ticket::SharedAccess.where(ticket_id: accessible_ticket_ids).find(params[:id])
    end
    
    shared_access.destroy!

    render json: true, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: __('Shared access not found.') }, status: :not_found
  end

  # GET /api/v1/ticket_shared_accesses/search?query=term
  def search
    query = params[:query].to_s.strip
    return render json: { result: [] } if query.length < 2

    users = User.where.not(id: current_user.id)
                .where('users.firstname ILIKE :q OR users.lastname ILIKE :q OR users.email ILIKE :q', q: "%#{query}%")
                .where(active: true)
                .joins('INNER JOIN roles_users ON roles_users.user_id = users.id')
                .joins('INNER JOIN roles ON roles.id = roles_users.role_id')
                .where('roles.name': 'Customer')
                .distinct
                .limit(10)

    assets = {}
    result = users.map do |user|
      assets = user.assets(assets)
      { id: user.id, type: 'User' }
    end

    render json: {
      result: result,
      assets: assets,
    }
  end

  private

  def ticket
    @ticket ||= begin
      # Admins can access any ticket (for API/automation purposes)
      if current_user.permissions?('admin')
        Ticket.find(params[:ticket_id])
      else
        # Customers can only access tickets they own or have shared access to
        accessible_tickets = Ticket.left_joins(:shared_accesses)
                                   .where('tickets.customer_id = :user_id OR ticket_shared_accesses.user_id = :user_id', user_id: current_user.id)
                                   .distinct
        accessible_tickets.find(params[:ticket_id])
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise Exceptions::UnprocessableEntity, __('Ticket not found.')
  end

  def target_user
    # Scope to active customer users only
    @target_user ||= User.joins('INNER JOIN roles_users ON roles_users.user_id = users.id')
                         .joins('INNER JOIN roles ON roles.id = roles_users.role_id')
                         .where('roles.name': 'Customer')
                         .where(active: true)
                         .find(params[:user_id])
  rescue ActiveRecord::RecordNotFound
    raise Exceptions::UnprocessableEntity, __('User not found.')
  end
end
