# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Transaction::Notification, 'shared access' do
  let(:agent)           { create(:agent, groups: [group]) }
  let(:group)           { create(:group) }
  let(:ticket_customer) { create(:customer) }
  let(:shared_customer) { create(:customer) }
  let(:ticket)          { create(:ticket, group: group, customer: ticket_customer) }

  before do
    Ticket::SharedAccess.share!(ticket, shared_customer, created_by: ticket_customer)
  end

  describe '#perform' do
    let(:item) do
      {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent.id,
        changes:   { 'state_id' => [1, 2] },
      }
    end

    let(:notification) { described_class.new(item) }

    it 'includes shared access customers in recipients' do
      notification.prepare_recipients_and_reasons
      recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
      expect(recipient_ids).to include(shared_customer.id)
    end

    it 'sets appropriate reason for shared access recipients' do
      notification.prepare_recipients_and_reasons
      expect(notification.recipients_reason[shared_customer.id])
        .to eq('You are receiving this because this ticket was shared with you.')
    end

    it 'enables both online and email channels for shared access customers' do
      notification.prepare_recipients_and_reasons
      shared_entry = notification.recipients_and_channels.find { |r| r[:user].id == shared_customer.id }
      expect(shared_entry[:channels]).to eq({ 'online' => true, 'email' => true })
    end

    context 'when type is create' do
      let(:item) do
        {
          object:    'Ticket',
          type:      'create',
          object_id: ticket.id,
          user_id:   agent.id,
        }
      end

      it 'does not include shared customers' do
        notification.prepare_recipients_and_reasons
        recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
        expect(recipient_ids).not_to include(shared_customer.id)
      end
    end

    context 'when type is reminder_reached' do
      let(:item) do
        {
          object:    'Ticket',
          type:      'reminder_reached',
          object_id: ticket.id,
          user_id:   agent.id,
        }
      end

      it 'does not include shared customers' do
        notification.prepare_recipients_and_reasons
        recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
        expect(recipient_ids).not_to include(shared_customer.id)
      end
    end

    context 'when type is escalation' do
      let(:item) do
        {
          object:    'Ticket',
          type:      'escalation',
          object_id: ticket.id,
          user_id:   agent.id,
        }
      end

      it 'does not include shared customers' do
        notification.prepare_recipients_and_reasons
        recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
        expect(recipient_ids).not_to include(shared_customer.id)
      end
    end

    context 'when type is escalation_warning' do
      let(:item) do
        {
          object:    'Ticket',
          type:      'escalation_warning',
          object_id: ticket.id,
          user_id:   agent.id,
        }
      end

      it 'does not include shared customers' do
        notification.prepare_recipients_and_reasons
        recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
        expect(recipient_ids).not_to include(shared_customer.id)
      end
    end
  end

  describe 'ticket customer always included' do
    let(:new_group)       { create(:group) }
    let(:new_agent)       { create(:agent, groups: [new_group]) }
    let(:new_customer)    { create(:customer) }
    let(:new_ticket)      { create(:ticket, group: new_group, customer: new_customer) }

    it 'includes ticket customer in update notifications' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: new_ticket.id,
        user_id:   new_agent.id,
        changes:   { 'state_id' => [1, 2] },
      }
      notification = described_class.new(item)
      notification.prepare_recipients_and_reasons
      recipient_ids = notification.recipients_and_channels.map { |r| r[:user].id }
      expect(recipient_ids).to include(new_customer.id)
    end
  end
end
