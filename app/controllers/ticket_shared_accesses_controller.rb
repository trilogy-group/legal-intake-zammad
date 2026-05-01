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

    # Use transaction to ensure share and notifications are atomic
    ActiveRecord::Base.transaction do
      Ticket::SharedAccess.share!(ticket, target_user, created_by: current_user)

      # Send notifications based on who is sharing
      send_sharing_notifications(ticket, target_user)
    end

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

  # GET /api/v1/ticket_shared_accesses/search?query=term&ticket_id=123
  def search
    query = params[:query].to_s.strip
    return render json: { result: [] } if query.length < 2

    users = search_users(query, excluded_user_ids)
    result, assets = build_search_response(users)

    render json: {
      result: result,
      assets: assets,
    }
  end

  private

  def send_sharing_notifications(ticket, shared_with_user)
    ticket_creator = ticket.customer
    is_creator_sharing = ticket_creator && ticket_creator.id == current_user.id

    # Always send online notification to user being shared with
    OnlineNotification.add(
      type: 'added',
      object: 'Ticket',
      o_id: ticket.id,
      seen: false,
      user_id: shared_with_user.id,
      created_by_id: current_user.id,
      updated_by_id: current_user.id,
    )

    # Shared customers will be notified through the main notification system
    # when actual ticket updates (comments, state changes) occur
    
    # Keep online notification for non-creator sharing
    # Don't send duplicate notification if the shared_with_user IS the ticket creator
    if !is_creator_sharing && ticket_creator && ticket_creator.id != shared_with_user.id
      OnlineNotification.add(
        type: 'update',
        object: 'Ticket',
        o_id: ticket.id,
        seen: false,
        user_id: ticket_creator.id,
        created_by_id: current_user.id,
        updated_by_id: current_user.id,
      )
    end
  end

  def excluded_user_ids
    excluded = [current_user.id]

    if params[:ticket_id].present?
      excluded << ticket.customer_id
      excluded.concat(Ticket::SharedAccess.where(ticket_id: params[:ticket_id]).pluck(:user_id))
    end

    excluded.compact
  end

  def search_users(query, excluded_ids)
    User.where.not(id: excluded_ids)
        .where('users.firstname ILIKE :q OR users.lastname ILIKE :q OR users.email ILIKE :q', q: "%#{query}%")
        .where(active: true)
        .joins('INNER JOIN roles_users ON roles_users.user_id = users.id')
        .joins('INNER JOIN roles ON roles.id = roles_users.role_id')
        .where('roles.name': 'Customer')
        .distinct
        .limit(10)
  end

  def build_search_response(users)
    assets = {}
    result = users.map do |user|
      assets = user.assets(assets)
      { id: user.id, type: 'User' }
    end
    [result, assets]
  end

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
