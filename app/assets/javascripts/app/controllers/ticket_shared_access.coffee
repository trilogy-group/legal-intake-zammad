class App.TicketSharedAccess extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Share')
  head: __('Share Ticket')
  large: false

  content: ->
    @sharedUsers = []
    @loadSharedUsers()

    @contentEl = $('<div>')

    @contentEl.append('<p class="text-muted">' + App.i18n.translateContent('Share this ticket with another customer so they can read and comment on it.') + '</p>')

    configure_attributes = {
      customer_id: {
        name: 'customer_id'
        display: __('Customer')
        tag: 'user_autocompletion'
        null: false
        placeholder: __('Enter name or email')
        minLength: 2
        disableCreateObject: true
        source: "#{App.Config.get('api_path')}/ticket_shared_accesses/search"
      }
    }

    @controller = new App.ControllerForm(
      model:           App.Ticket
      mixedAttributes: configure_attributes
      screen:          'edit'
      autofocus:       true
    )

    @contentEl.append(@controller.form)
    @contentEl.append('<hr><h3>' + App.i18n.translateContent('Currently shared with') + '</h3>')
    @contentEl.append('<div class="js-sharedUsersList"><p class="text-muted">' + App.i18n.translateContent('Loading...') + '</p></div>')

    @contentEl

  loadSharedUsers: =>
    @ajax(
      id:   "ticket_shared_accesses_#{@ticket_id}"
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/ticket_shared_accesses?ticket_id=#{@ticket_id}"
      success: (data) =>
        App.Collection.loadAssets(data.assets) if data.assets
        @sharedUsers = data.shared_accesses || []
        @renderSharedUsers()
      error: =>
        @$('.js-sharedUsersList').html('<p class="text-muted">' + App.i18n.translateContent('Could not load shared users.') + '</p>')
    )

  renderSharedUsers: =>
    list = @$('.js-sharedUsersList')
    if @sharedUsers.length is 0
      list.html('<p class="text-muted">' + App.i18n.translateContent('Not shared with anyone yet.') + '</p>')
      return

    currentUser = App.User.current()
    ticket = App.Ticket.find(@ticket_id)
    isTicketOwner = ticket && ticket.customer_id is currentUser.id

    html = '<ul class="list-unstyled">'
    for access in @sharedUsers
      user = App.User.find(access.user_id)
      displayName = if user then user.displayName() else "User ##{access.user_id}"
      canRemove = isTicketOwner || access.user_id is currentUser.id
      removeBtn = if canRemove
        "<a href=\"#\" class=\"btn btn--text btn--small js-removeSharedAccess\" data-id=\"#{access.id}\" style=\"color: #e74c3c;\">#{App.i18n.translateContent('Remove')}</a>"
      else
        ''
      html += "<li class=\"shared-user-item\" style=\"padding: 5px 0; display: flex; justify-content: space-between; align-items: center;\">
        <span>#{App.Utils.htmlEscape(displayName)}</span>
        #{removeBtn}
      </li>"
    html += '</ul>'
    list.html(html)

    list.find('.js-removeSharedAccess').on('click', (e) =>
      e.preventDefault()
      accessId = $(e.currentTarget).data('id')
      @removeSharedAccess(accessId)
    )

  removeSharedAccess: (accessId) =>
    @ajax(
      id:   "ticket_shared_access_remove_#{accessId}"
      type: 'DELETE'
      url:  "#{App.Config.get('api_path')}/ticket_shared_accesses/#{accessId}?ticket_id=#{@ticket_id}"
      success: =>
        @loadSharedUsers()
        @notify(
          type: 'success'
          msg:  App.i18n.translateContent('Shared access removed.')
        )
      error: (xhr) =>
        @notify(
          type: 'error'
          msg:  App.i18n.translateContent('Failed to remove shared access.')
        )
    )

  onSubmit: (e) =>
    params = @formParam(e.target)

    if !params.customer_id
      @notify(
        type: 'error'
        msg:  App.i18n.translateContent('Please select a customer to share with.')
      )
      return

    @ajax(
      id:   'ticket_shared_access_create'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/ticket_shared_accesses"
      data: JSON.stringify(
        ticket_id: @ticket_id
        user_id:   params.customer_id
      )
      processData: true
      success: =>
        @notify(
          type: 'success'
          msg:  App.i18n.translateContent('Ticket shared successfully!')
        )
        @loadSharedUsers()
        @controller.form.find('[name=customer_id]').val('')
        @controller.form.find('.token').remove()
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @notify(
          type: 'error'
          msg:  data.error || App.i18n.translateContent('Failed to share ticket.')
        )
    )
