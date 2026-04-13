# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketSharedAccessesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # GET /api/v1/ticket_shared_accesses?ticket_id=123
  def index
    list = ticket.shared_accesses

    render json: {
      shared_accesses: list,
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

  private

  def ticket
    @ticket ||= Ticket.find(params[:ticket_id])
  end

  def target_user
    @target_user ||= User.find(params[:user_id])
  end
end
