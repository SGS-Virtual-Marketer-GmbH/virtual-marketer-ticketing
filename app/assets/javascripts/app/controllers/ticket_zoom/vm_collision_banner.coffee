# Loud, readable notice when a colleague has the same ticket open.
#
# Zammad already tells you, but only as a 40px avatar in the bottom bar with a
# small pen icon -- easy to miss, which is how two people end up answering the
# same customer. This renders a banner above the ticket from the very same
# data (the shared taskbar preferences), so there is nothing new to keep in
# sync on the server.
#
# Two levels, because they mean different things:
#   - someone has typed something (the task state is "changed", i.e. a reply
#     or note in progress): warning, "talk before you answer"
#   - someone merely has the ticket open: calm information
# Anyone idle for 5+ minutes is left out; an abandoned browser tab must not
# keep a warning up. Deliberately NOT a hard lock for the same reason: a lock
# that outlives a closed laptop blocks the ticket for everybody.
class App.VmCollisionBanner extends App.Controller
  IDLE_MS: 300000

  constructor: ->
    super
    @subscribeId = App.TaskManager.preferencesSubscribe(@taskKey, @render)
    App.TaskManager.preferencesTrigger(@taskKey)
    # idleness is a function of time, not of new data
    @intervalId = @interval(
      => App.TaskManager.preferencesTrigger(@taskKey)
      60000
      'vm-collision-banner'
    )

  release: =>
    App.TaskManager.preferencesUnsubscribe(@subscribeId) if @subscribeId
    @clearInterval(@intervalId) if @intervalId

  others: (preferences) =>
    currentUserId = App.Session.get('id')
    now = new Date().getTime()
    found = []
    for task in (preferences?.tasks || [])
      continue if task.user_id is currentUserId
      for key, app of (task.apps || {})
        continue if !app.last_contact
        continue if now - new Date(app.last_contact).getTime() > @IDLE_MS
        found.push(user_id: task.user_id, editing: !!app.changed)
        break
    found

  render: (preferences) =>
    return if !preferences
    found = @others(preferences)

    signature = _.map(found, (f) -> "#{f.user_id}:#{f.editing}").join(',')
    return if signature is @lastSignature
    @lastSignature = signature

    if found.length is 0
      @el.addClass('hide').empty()
      return

    editing = _.filter(found, (f) -> f.editing)
    level   = if editing.length > 0 then 'editing' else 'viewing'
    people  = if level is 'editing' then editing else found

    names = []
    pending = people.length
    done = =>
      pending -= 1
      @show(level, names) if pending is 0
    for person in people
      App.User.full(person.user_id, (user) =>
        names.push(user.displayName()) if user
        done()
      )

  show: (level, names) =>
    return if names.length is 0
    who = if names.length is 1 then names[0] else "#{names[...-1].join(', ')} und #{names[names.length - 1]}"
    if level is 'editing'
      text = "<strong>#{App.Utils.htmlEscape(who)}</strong> #{if names.length is 1 then 'bearbeitet' else 'bearbeiten'} dieses Ticket gerade und #{if names.length is 1 then 'hat' else 'haben'} bereits etwas in Arbeit (Antwort oder Notiz). Bitte kurz abstimmen, bevor du antwortest, sonst bekommt der Kunde womöglich zwei Antworten."
    else
      text = "<strong>#{App.Utils.htmlEscape(who)}</strong> #{if names.length is 1 then 'hat' else 'haben'} dieses Ticket ebenfalls geöffnet."
    @el
      .removeClass('hide vm-collab--editing vm-collab--viewing')
      .addClass("vm-collab--#{level}")
      .attr('role', 'alert')
      .html("<span class=\"vm-collab-icon\">#{if level is 'editing' then '&#9998;' else '&#128065;'}</span><span>#{text}</span>")
