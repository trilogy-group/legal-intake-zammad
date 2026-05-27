# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

# Tests for email notification priority rules defined in issue #10.
#
# Priority order: Comment > Status Change > Owner Change
#
# Scenario matrix:
#   1. Status change + Owner change          -> only status notification
#   2. Status change + Comment + Owner change -> only comment notification
#   3. Comment + Owner change                -> only comment notification
#   4. Comment + Status change               -> only comment notification
#   5. Comment only                          -> comment notification
#   6. Status only                           -> status notification
#   7. Owner change only                     -> assignment notification (owner + full-access agents only, NOT customers)
#
RSpec.describe Transaction::Notification, 'email notification priority rules' do
  let(:group)           { create(:group) }
  let(:agent_owner)     { create(:agent, groups: [group]) }
  let(:agent_other)     { create(:agent, groups: [group]) }
  let(:customer)        { create(:customer) }
  let(:shared_customer) { create(:customer) }
  let(:open_state)      { Ticket::State.find_by(name: 'open') }
  let(:closed_state)    { Ticket::State.find_by(name: 'closed') }
  let(:ticket) do
    create(:ticket, group: group, customer: customer, owner: agent_owner,
                    state: open_state)
  end

  before do
    Ticket::SharedAccess.share!(ticket, shared_customer, created_by: customer)
    allow(NotificationFactory::Mailer).to receive(:deliver)
    allow(NotificationFactory::Mailer).to receive(:template).and_return({ subject: 'subj', body: 'body' })
  end

  # -------------------------------------------------------------------------
  # Scenario 1: Status change + Owner change → only status notification
  # -------------------------------------------------------------------------
  describe 'scenario 1: status change + owner change together' do
    it 'sends exactly one notification and it is for the state change' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   {
          'state_id' => [open_state.id, closed_state.id],
          'owner_id' => [1, agent_owner.id],
        },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_state_closed')).once
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_assigned'))
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 2: Status change + Comment + Owner change → only comment notification
  # -------------------------------------------------------------------------
  describe 'scenario 2: status change + comment + owner change together' do
    it 'sends exactly one notification and it is for the comment' do
      article = create(:ticket_article, ticket: ticket, created_by: customer)
      item = {
        object:     'Ticket',
        type:       'update',
        object_id:  ticket.id,
        article_id: article.id,
        user_id:    customer.id,
        changes:    {
          'state_id' => [open_state.id, closed_state.id],
          'owner_id' => [1, agent_owner.id],
        },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_comment_added')).once
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_state_closed'))
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_assigned'))
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 3: Comment + Owner change → only comment notification
  # -------------------------------------------------------------------------
  describe 'scenario 3: comment + owner change together' do
    it 'sends only the comment notification' do
      article = create(:ticket_article, ticket: ticket, created_by: customer)
      item = {
        object:     'Ticket',
        type:       'update',
        object_id:  ticket.id,
        article_id: article.id,
        user_id:    customer.id,
        changes:    { 'owner_id' => [1, agent_owner.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_comment_added')).once
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_assigned'))
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 4: Comment + Status change → only comment notification
  # -------------------------------------------------------------------------
  describe 'scenario 4: comment + status change together' do
    it 'sends only the comment notification, not a separate state notification' do
      article = create(:ticket_article, ticket: ticket, created_by: customer)
      item = {
        object:     'Ticket',
        type:       'update',
        object_id:  ticket.id,
        article_id: article.id,
        user_id:    customer.id,
        changes:    { 'state_id' => [open_state.id, closed_state.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:deliver).once
      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_comment_added')).once
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_state_closed'))
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 5: Comment only → comment notification
  # -------------------------------------------------------------------------
  describe 'scenario 5: comment only' do
    it 'sends a comment notification' do
      article = create(:ticket_article, ticket: ticket, created_by: customer)
      item = {
        object:     'Ticket',
        type:       'update',
        object_id:  ticket.id,
        article_id: article.id,
        user_id:    customer.id,
        changes:    {},
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_comment_added')).once
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 6: Status only → status notification
  # -------------------------------------------------------------------------
  describe 'scenario 6: status change only' do
    it 'sends a state change notification' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   { 'state_id' => [open_state.id, closed_state.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_state_closed')).once
      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: 'ticket_assigned'))
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 7: Owner change only → assignment notification
  # -------------------------------------------------------------------------
  describe 'scenario 7: owner change only' do
    it 'sends an assignment notification' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   { 'owner_id' => [1, agent_owner.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:template)
        .with(hash_including(template: 'ticket_assigned')).once
    end

    it 'does not send a state notification' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   { 'owner_id' => [1, agent_owner.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).not_to have_received(:template)
        .with(hash_including(template: a_string_matching(/ticket_state/)))
    end

    it 'does not include the ticket customer in the assignment email CC' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   { 'owner_id' => [1, agent_owner.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:deliver) do |**kwargs|
        cc = kwargs[:cc]
        expect(cc).to satisfy('not include customer email') do |val|
          val.nil? || val.blank? || !val.include?(customer.email)
        end
      end
    end

    it 'does not include shared customers in the assignment email CC' do
      item = {
        object:    'Ticket',
        type:      'update',
        object_id: ticket.id,
        user_id:   agent_other.id,
        changes:   { 'owner_id' => [1, agent_owner.id] },
      }
      described_class.new(item).perform

      expect(NotificationFactory::Mailer).to have_received(:deliver) do |**kwargs|
        cc = kwargs[:cc]
        expect(cc).to satisfy('not include shared customer email') do |val|
          val.nil? || val.blank? || !val.include?(shared_customer.email)
        end
      end
    end
  end
end
