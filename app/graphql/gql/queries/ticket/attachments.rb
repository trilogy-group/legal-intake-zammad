# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Attachments < BaseQuery

    description 'Fetch ticket attachments by ticket ID'

    argument :ticket_id, GraphQL::Types::ID, loads: Gql::Types::TicketType, description: 'The ticket to fetch attachments for'

    type [Gql::Types::StoredFileType, { null: false }], null: false

    def resolve(ticket:)
      Service::Ticket::Attachment::List
        .new(current_user: context.current_user)
        .execute(ticket:)
    end
  end
end
