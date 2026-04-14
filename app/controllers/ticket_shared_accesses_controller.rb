# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketSharedAccessesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # GET /api/v1/ticket_shared_accesses?ticket_id=123
  def index
    list = ticket.shared_accesses.includes(:user)

    assets = {}
    list.each { |sa| assets = sa.user.assets(assets) }

    render json: {
      shared_accesses: list,
      assets:          assets,
    }
  end

  # POST /api/v1/ticket_shared_accesses
  def create
    Ticket::SharedAccess.share!(ticket, target_user, created_by: current_user)

    render json: true, status: :created
  end

  # DELETE /api/v1/ticket_shared_accesses/:id
  def destroy
    Ticket::SharedAccess.find(params[:id]).destroy!

    render json: true, status: :ok
  end

  # GET /api/v1/ticket_shared_accesses/search?query=term
  def search
    query = params[:query].to_s.strip
    return render json: { result: [] } if query.length < 2

    users = User.where.not(id: current_user.id)
                .where('users.firstname ILIKE :q OR users.lastname ILIKE :q OR users.email ILIKE :q', q: "%#{query}%")
                .where(active: true)
                .limit(10)

    assets = {}
    result = users.map do |user|
      assets = user.assets(assets)
      { id: user.id, type: 'User' }
    end

    render json: {
      result:    result,
      assets:    assets,
    }
  end

  private

  def ticket
    @ticket ||= Ticket.find(params[:ticket_id])
  end

  def target_user
    @target_user ||= User.find(params[:user_id])
  end
end
