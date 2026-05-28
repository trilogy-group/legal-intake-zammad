class ProfileEmailNotifications extends App.ControllerSubContent
  @requiredPermission: 'user_preferences.email_notifications'
  header: __('Email Notifications')
  events:
    'change .js-emailNotificationsToggle': 'update'

  constructor: ->
    super
    App.User.full(App.Session.get().id, @render, true, true)

  render: =>
    user = App.User.find(App.Session.get('id'))
    preferences = user.preferences || {}
    # Default is enabled when no preference has been stored
    enabled = if preferences.email_notifications_enabled?
      preferences.email_notifications_enabled
    else
      true

    @html App.view('profile/email_notifications')(
      enabled: enabled
    )

  update: (e) =>
    enabled = $(e.target).is(':checked')

    @ajax(
      id:          'email_notifications_update'
      type:        'PUT'
      url:         "#{@apiPath}/users/email_notifications"
      data:        JSON.stringify({ enabled: enabled })
      processData: true
      success:     @success
      error:       @error
    )

  success: (data, status, xhr) =>
    App.User.full(
      App.Session.get('id'),
      =>
        App.Event.trigger('ui:rerender')
        @notify(
          type: 'success'
          msg:  __('Update successful.')
        )
      ,
      true
    )

  error: (xhr, status, error) =>
    @render()
    data = JSON.parse(xhr.responseText)
    @notify(
      type: 'error'
      msg:  data.error || data.message
    )

App.Config.set('EmailNotifications', { prio: 1100, name: __('Email Notifications'), parent: '#profile', target: '#profile/email_notifications', controller: ProfileEmailNotifications, permission: ['user_preferences.email_notifications+ticket.customer'] }, 'NavBarProfile')
