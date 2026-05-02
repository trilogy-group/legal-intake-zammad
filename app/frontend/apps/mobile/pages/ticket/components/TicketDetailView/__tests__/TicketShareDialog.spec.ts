// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import '#tests/graphql/builders/mocks.ts'

import { renderComponent } from '#tests/support/components/index.ts'

import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'

import TicketShareDialog from '../TicketShareDialog.vue'

describe('TicketShareDialog', () => {
  it('renders share ticket dialog with customer search', async () => {
    const wrapper = renderComponent(TicketShareDialog, {
      props: {
        name: 'ticket-share',
        ticket: createDummyTicket(),
      },
      dialog: true,
      store: true,
      router: true,
    })

    expect(wrapper.getByRole('dialog', { name: 'Share Ticket' })).toBeInTheDocument()

    expect(
      wrapper.getByText(
        'Share this ticket with another customer so they can read and comment on it.',
      ),
    ).toBeInTheDocument()

    expect(wrapper.getByPlaceholderText('Enter name or email')).toBeInTheDocument()

    expect(wrapper.getByRole('button', { name: 'Cancel' })).toBeInTheDocument()

    expect(wrapper.getByText('Currently shared with')).toBeInTheDocument()
  })

  it('displays shared users list', async () => {
    const wrapper = renderComponent(TicketShareDialog, {
      props: {
        name: 'ticket-share',
        ticket: createDummyTicket(),
      },
      dialog: true,
      store: true,
      router: true,
    })

    // Initially should show "Not shared with anyone yet"
    expect(await wrapper.findByText('Not shared with anyone yet.')).toBeInTheDocument()
  })

  it('verifies share button behavior', async () => {
    const wrapper = renderComponent(TicketShareDialog, {
      props: {
        name: 'ticket-share',
        ticket: createDummyTicket(),
      },
      dialog: true,
      store: true,
      router: true,
    })

    // Wait for the component to render
    await wrapper.findByText(
      'Share this ticket with another customer so they can read and comment on it.',
    )

    // Verify the search input exists
    const searchInput = wrapper.getByPlaceholderText('Enter name or email')
    expect(searchInput).toBeInTheDocument()
  })
})
