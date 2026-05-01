// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import '#tests/graphql/builders/mocks.ts'

import { renderComponent } from '#tests/support/components/index.ts'

import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'

import TicketShareFlyout from '../TicketShareFlyout.vue'

describe('TicketShareFlyout', () => {
  it('renders share ticket flyout with customer search', async () => {
    const wrapper = renderComponent(TicketShareFlyout, {
      props: {
        ticket: createDummyTicket(),
      },
      flyout: true,
      store: true,
      form: true,
      router: true,
    })

    expect(wrapper.getByRole('heading', { name: 'Share Ticket', level: 2 })).toBeInTheDocument()

    expect(
      wrapper.getByText(
        'Share this ticket with another customer so they can read and comment on it.',
      ),
    ).toBeInTheDocument()

    expect(wrapper.getByPlaceholderText('Enter name or email')).toBeInTheDocument()

    expect(wrapper.getByText('Currently shared with')).toBeInTheDocument()
  })

  it('displays shared users list', async () => {
    const wrapper = renderComponent(TicketShareFlyout, {
      props: {
        ticket: createDummyTicket(),
      },
      flyout: true,
      store: true,
      form: true,
      router: true,
    })

    // Initially should show "Not shared with anyone yet"
    expect(await wrapper.findByText('Not shared with anyone yet.')).toBeInTheDocument()
  })
})
