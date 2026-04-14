# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::SharedAccess::Share < BaseMutation
    description 'Share a ticket with another customer, granting them read and comment access.'

    argument :ticket_id, GraphQL::Types::ID, description: 'The ticket to share'
    argument :user_id, GraphQL::Types::ID, description: 'The customer user to share with'

    field :success, Boolean, description: 'Was the mutation successful?'
    field :errors, [Gql::Types::UserErrorType], null: true, description: 'Errors, if any'

    requires_permission 'ticket.customer'

    def resolve(ticket_id:, user_id:)
      ticket = Gql::ZammadSchema.authorized_object_from_id(ticket_id, user: context.current_user, query: :show?, type: ::Ticket)

      target_user_id = Gql::ZammadSchema.internal_id_from_id(user_id, type: User)
      target_user = User.find(target_user_id)

      authorize_share!(ticket, context.current_user)
      validate_target_user!(target_user)

      ::Ticket::SharedAccess.share!(ticket, target_user, created_by: context.current_user)
      { success: true }
    rescue Exceptions::Forbidden => e
      error_response({ message: e.message })
    rescue ActiveRecord::RecordNotFound
      error_response({ message: __('User not found.') })
    end

    private

    def authorize_share!(ticket, user)
      return if ticket.customer_id == user.id
      return if ::Ticket::SharedAccess.shared_with?(ticket, user)

      raise Exceptions::Forbidden, __('You are not authorized to share this ticket.')
    end

    def validate_target_user!(user)
      return if user.permissions?('ticket.customer')

      raise Exceptions::Forbidden, __('Ticket can only be shared with customer users.')
    end
  end
end
