# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Transaction::Notification
  include ChecksHumanChanges

=begin
  {
    object: 'Ticket',
    type: 'update',
    object_id: 123,
    interface_handle: 'application_server', # application_server|websocket|scheduler
    changes: {
      'attribute1' => [before, now],
      'attribute2' => [before, now],
    },
    created_at: Time.zone.now,
    user_id: 123,
  },
=end

  attr_accessor :recipients_and_channels, :recipients_reason

  def initialize(item, params = {})
    @item                    = item
    @params                  = params
    @recipients_and_channels = []
    @recipients_reason       = {}
  end

  def ticket
    @ticket ||= Ticket.find_by(id: @item[:object_id])
  end

  def article_by_item
    return if !@item[:article_id]

    article = Ticket::Article.find(@item[:article_id])

    # ignore notifications
    sender = Ticket::Article::Sender.lookup(id: article.sender_id)
    if sender&.name == 'System'
      return if @item[:changes].blank? && article.preferences[:notification] != true

      if article.preferences[:notification] != true
        article = nil
      end
    end

    article
  end

  def article
    @article ||= article_by_item
  end

  def current_user
    @current_user ||= User.lookup(id: @item[:user_id]) || User.lookup(id: 1)
  end

  def perform

    # return if we run import mode
    return if Setting.get('import_mode')
    return if %w[Ticket Ticket::Article].exclude?(@item[:object])
    return if @params[:disable_notification]
    return if !ticket

    prepare_recipients_and_reasons

    # For assignment notifications, send ONE email with CC instead of separate emails
    if @item[:type] == 'update' && @item[:changes]&.key?('owner_id')
      send_assignment_notification_with_cc
    else
      # send notifications
      recipients_and_channels.each do |recipient_settings|
        ActiveRecord::Base.transaction do
          send_to_single_recipient(recipient_settings)
        end
      end
    end
  end

  def prepare_recipients_and_reasons

    # loop through all group users
    possible_recipients = possible_recipients_of_group(ticket.group_id)

    # loop through all mention users
    mention_users = Mention.where(mentionable_type: @item[:object], mentionable_id: @item[:object_id]).map(&:user)
    if mention_users.present?

      # only notify if read permission on group are given
      mention_users.each do |mention_user|
        next if !mention_user.group_access?(ticket.group_id, 'read')

        possible_recipients.push mention_user
        @recipients_reason[mention_user.id] = __('You are receiving this because you were mentioned in this ticket.')
      end
    end

    # apply owner
    if ticket.owner_id != 1
      possible_recipients.push ticket.owner
      @recipients_reason[ticket.owner_id] = __('You are receiving this because you are a member of the group of this ticket.')
    end

    # apply ticket customer
    if ticket.customer_id && ticket.customer_id != 1
      customer = User.find_by(id: ticket.customer_id)
      if customer&.active? && !possible_recipients.include?(customer)
        # Only add customer for updates, not for creation
        # Customers shouldn't receive confirmation emails when they create tickets
        if @item[:type] != 'create'
          possible_recipients.push customer
          @recipients_reason[ticket.customer_id] = __('You are receiving this because you created this ticket.')
        end
      end
    end

    # apply out of office agents
    possible_recipients_additions = Set.new
    possible_recipients.each do |user|
      ooo_replacements(
        user:         user,
        replacements: possible_recipients_additions,
        reasons:      recipients_reason,
        ticket:       ticket,
      )
    end

    if possible_recipients_additions.present?
      # join unique entries
      possible_recipients |= possible_recipients_additions.to_a
    end

    recipients_reason_by_notifications_settings(possible_recipients)

    # Only notify shared customers for actual ticket updates (comments, field changes)
    # Exclude internal operational events (create, reminders, escalations)
    add_shared_access_recipients if @item[:type] == 'update'
  end

  def add_shared_access_recipients
    shared_users = Ticket::SharedAccess.where(ticket_id: ticket.id).includes(:user).map(&:user)
    already_added_ids = @recipients_and_channels.to_set { |r| r[:user].id }

    shared_users.each do |shared_user|
      next if already_added_ids.include?(shared_user.id)
      next if !shared_user.active?

      # Check user's notification preferences
      result = NotificationFactory::Mailer.notification_settings(shared_user, ticket, @item[:type])

      # If no preferences configured, default to allowing notifications
      # (shared access is an explicit opt-in, so notifications are expected)
      if !result
        result = {
          user:     shared_user,
          channels: { 'online' => true, 'email' => true },
        }
      end

      @recipients_and_channels.push(result)
      @recipients_reason[shared_user.id] = __('You are receiving this because this ticket was shared with you.')
    end
  end

  def recipients_reason_by_notifications_settings(possible_recipients)
    already_checked_recipient_ids = {}
    possible_recipients.each do |user|
      result = NotificationFactory::Mailer.notification_settings(user, ticket, @item[:type])
      next if !result
      next if already_checked_recipient_ids[user.id]

      already_checked_recipient_ids[user.id] = true
      @recipients_and_channels.push result
      next if recipients_reason[user.id]

      @recipients_reason[user.id] = __('You are receiving this because you are a member of the group of this ticket.')
    end
  end

  def recipient_myself?(user)
    return false if @params[:interface_handle] != 'application_server'
    
    if @item[:type] == 'create' && user.id == ticket.customer_id
      return false
    end
    
    return true if article&.updated_by_id == user.id
    return true if !article && @item[:user_id] == user.id

    false
  end

  def send_assignment_notification_with_cc
    return if recipients_and_channels.blank?

    # Find the owner (To:) and others (CC:)
    owner = ticket.owner
    owner_recipient = recipients_and_channels.find { |r| r[:user].id == owner.id }
    
    # If owner is not in recipients, something went wrong
    return if !owner_recipient

    # Collect CC recipients (customer + shared customers)
    cc_recipients = recipients_and_channels.reject { |r| r[:user].id == owner.id }
    
    # Send online notifications to all recipients
    recipients_and_channels.each do |recipient_settings|
      user = recipient_settings[:user]
      next if !recipient_settings[:channels]['online']
      
      send_to_single_recipient_online(user, ticket, article)
    end

    # Prepare email recipients
    # Only send email if owner wants email notifications
    return if !owner_recipient[:channels]['email']

    # Build CC list from recipients who want email
    cc_emails = cc_recipients
      .select { |r| r[:channels]['email'] }
      .map { |r| r[:user].email }
      .compact
      .join(', ')

    # Get template and objects
    changes = @item[:changes] || {}
    template = 'ticket_assigned'
    
    attachments = []
    if article
      attachments = article.attachments_inline
    end

    # Build email body
    result = NotificationFactory::Mailer.template(
      template:   template,
      locale:     owner[:preferences][:locale],
      objects:    {
        ticket:       ticket,
        article:      article,
        recipient:    owner,
        current_user: current_user,
        changes:      changes,
        reason:       recipients_reason[owner.id],
      },
      standalone: false,
    )

    # Rebuild subject if needed
    if ticket.respond_to?(:subject_build)
      result[:subject] = ticket.subject_build(result[:subject])
    end

    # Prepare body
    if result[:body]
      result[:body] = HtmlSanitizer.adjust_inline_image_size(result[:body])
      result[:body] = HtmlSanitizer.dynamic_image_size(result[:body])
    end

    # Send one email with CC
    NotificationFactory::Mailer.deliver(
      recipient:    owner,
      subject:      result[:subject],
      body:         result[:body],
      content_type: 'text/html',
      message_id:   "<notification.#{DateTime.current.to_fs(:number)}.#{ticket.id}.#{owner.id}.#{SecureRandom.uuid}@#{Setting.get('fqdn')}>",
      references:   ticket.get_references,
      attachments:  attachments,
      cc:           cc_emails.present? ? cc_emails : nil,
    )

    # Add notification history for owner
    add_recipient_list_to_history(ticket, owner, owner_recipient[:channels].keys, 'update')
    
    # Add notification history for CC recipients
    cc_recipients.each do |r|
      add_recipient_list_to_history(ticket, r[:user], r[:channels].keys, 'update') if r[:channels]['email']
    end

    Rails.logger.debug { "sent assignment email to owner (#{ticket.id}/#{owner.email}) with CC (#{cc_emails})" }
  end

  def send_to_single_recipient(recipient_settings)
    user     = recipient_settings[:user]
    channels = recipient_settings[:channels]

    # ignore user who changed it by him self via web
    return if recipient_myself?(user)

    # ignore inactive users
    return if !user.active?

    blocked_in_days = user.mail_delivery_failed_blocked_days
    if blocked_in_days.positive?
      Rails.logger.info "Send no system notifications to #{user.email} because email is marked as mail_delivery_failed for #{blocked_in_days} day(s)"
      return
    end

    # ignore if no changes has been done
    changes = human_changes(@item[:changes], ticket, user)
    return if @item[:type] == 'update' && !article && changes.blank?

    # check if today already notified
    if %w[reminder_reached escalation escalation_warning].include?(@item[:type]) && !Ticket::DailyEventLock.lock!(
      lock_type:      'notification',
      lock_activator: @item[:type],
      ticket:,
      related_object: user,
    )
      return
    end

    # create online notification
    used_channels = []

    if channels['online']
      used_channels.push 'online'

      send_to_single_recipient_online(user, ticket, article)
    end

    if channels['email'] && user.email.present?
      used_channels.push 'email'

      send_to_single_recipient_email(user, ticket, article, changes)
    end

    add_recipient_list_to_history(ticket, user, used_channels, @item[:type])
  end

  def add_recipient_list_to_history(ticket, user, channels, type)
    return if channels.blank?

    identifier     = user.email.presence || user.login
    recipient_list = "#{identifier}(#{type}:#{channels.join(',')})"

    History.add(
      o_id:           ticket.id,
      history_type:   'notification',
      history_object: 'Ticket',
      value_to:       recipient_list,
      created_by_id:  @item[:user_id] || 1
    )
  end

  private

  def ooo_replacements(user:, replacements:, ticket:, reasons:)
    replacement = user.out_of_office_agent

    return if !replacement

    return if !TicketPolicy.new(replacement, ticket).agent_read_access?

    return if !replacements.add?(replacement)

    reasons[replacement.id] = __('You are receiving this because you are out-of-office replacement for a participant of this ticket.')
  end

  def possible_recipients_of_group(group_id)
    Rails.cache.fetch("User/notification/possible_recipients_of_group/#{group_id}/#{User.latest_change}", expires_in: 20.seconds) do
      User.group_access(group_id, 'full').sort_by(&:login)
    end
  end

  def send_to_single_recipient_online(user, ticket, article)
    created_by_id = @item[:user_id] || 1

    # delete old notifications
    if @item[:type] == 'reminder_reached'
      seen = false
      created_by_id = 1
      OnlineNotification.remove_by_type('Ticket', ticket.id, @item[:type], user)

    elsif %w[escalation escalation_warning].include?(@item[:type])
      seen = false
      created_by_id = 1
      OnlineNotification.remove_by_type('Ticket', ticket.id, 'escalation', user)
      OnlineNotification.remove_by_type('Ticket', ticket.id, 'escalation_warning', user)

    # on updates without state changes create unseen messages
    elsif @item[:type] != 'create' && (@item[:changes].blank? || @item[:changes]['state_id'].blank?)
      seen = false
    else
      seen = OnlineNotification.seen_state?(ticket, user.id)
    end

    OnlineNotification.add(
      type:          @item[:type],
      object:        @item[:object],
      o_id:          @item[:object].eql?('Ticket') ? ticket.id : article.id,
      seen:          seen,
      created_by_id: created_by_id,
      user_id:       user.id,
    )
    Rails.logger.debug { "sent ticket online notification to agent (#{@item[:type]}/#{ticket.id}/#{user.email})" }
  end

  def send_to_single_recipient_email(user, ticket, article, changes)
    # get user based notification template
    # if create, send create message / block update messages
    template = case @item[:type]
               when 'create'
                 'ticket_create'
               when 'update'
                 determine_update_template(ticket, article, changes)
               when 'reminder_reached'
                 'ticket_reminder_reached'
               when 'escalation'
                 'ticket_escalation'
               when 'escalation_warning'
                 'ticket_escalation_warning'
               when 'update.merged_into'
                 'ticket_update_merged_into'
               when 'update.received_merge'
                 'ticket_update_received_merge'
               when 'update.reaction'
                 'ticket_article_update_reaction'
               else
                 raise "unknown type for notification #{@item[:type]}"
               end

    attachments = []
    if article
      attachments = article.attachments_inline
    end
    NotificationFactory::Mailer.notification(
      template:    template,
      user:        user,
      objects:     {
        ticket:       ticket,
        article:      article,
        recipient:    user,
        current_user: current_user,
        changes:      changes,
        reason:       recipients_reason[user.id],
      },
      message_id:  "<notification.#{DateTime.current.to_fs(:number)}.#{ticket.id}.#{user.id}.#{SecureRandom.uuid}@#{Setting.get('fqdn')}>",
      references:  ticket.get_references,
      main_object: ticket,
      attachments: attachments,
    )
    Rails.logger.debug { "sent ticket email notification to agent (#{@item[:type]}/#{ticket.id}/#{user.email})" }
  end

  def determine_update_template(ticket, article, changes)
    # Priority order matters - check most specific conditions first
    
    # 1. Ownership/Assignment changed (check before article to avoid false positive)
    return 'ticket_assigned' if changes&.key?('owner_id')
    
    # 2. Comment/Article added
    return 'ticket_comment_added' if article
    
    # 3. State changed to specific values
    if changes&.key?('state_id')
      new_state_id = changes['state_id'].last
      old_state_id = changes['state_id'].first
      
      # Check if changed to closed/resolved
      resolved_states = Ticket::State.where(name: %w[closed merged removed]).pluck(:id)
      return 'ticket_state_resolved' if resolved_states.include?(new_state_id)
      
      # Check if reopened (from closed to open)
      open_states = Ticket::State.where(name: %w[new open]).pluck(:id)
      return 'ticket_state_reopened' if resolved_states.include?(old_state_id) && open_states.include?(new_state_id)
      
      # Other state changes
      return 'ticket_state_changed'
    end
    
    # 4. Priority changed
    return 'ticket_priority_changed' if changes&.key?('priority_id')
    
    # 5. Fallback for any other updates
    'ticket_update'
  end
end
