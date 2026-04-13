# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::SharedAccess::Unshare < BaseMutation
    description 'Remove shared access from a ticket for a customer.'

    argument :ticket_id, GraphQL::Types::ID, description: 'The ticket to unshare'
    argument :user_id, GraphQL::Types::ID, description: 'The customer user to remove access from'

    field :success, Boolean, description: 'Was the mutation successful?'
    field :errors, [Gql::Types::UserErrorType], null: true, description: 'Errors, if any'

    requires_permission 'ticket.agent', 'ticket.customer'

    def resolve(ticket_id:, user_id:)
      ticket = Gql::ZammadSchema.authorized_object_from_id(ticket_id, user: context.current_user, query: :show?, type: ::Ticket)

      target_user_id = Gql::ZammadSchema.internal_id_from_id(user_id, type: User)
      target_user = User.find(target_user_id)

      authorize_unshare!(ticket, target_user, context.current_user)

      ::Ticket::SharedAccess.unshare!(ticket, target_user)
      { success: true }
    rescue Exceptions::Forbidden => e
      error_response({ message: e.message })
    rescue ActiveRecord::RecordNotFound
      error_response({ message: __('Shared access not found.') })
    end

    private

    def authorize_unshare!(ticket, target_user, current_user)
      return if TicketPolicy.new(current_user, ticket).agent_read_access?
      return if ticket.customer_id == current_user.id
      return if target_user.id == current_user.id

      raise Exceptions::Forbidden, __('You are not authorized to remove shared access from this ticket.')
    end
  end
end
