# The one place the VM screens (tile board, workspace category bar) get their
# ticket counts from.
#
# Why this exists instead of App.OverviewIndexCollection: that collection is
# fed by the websocket push and hands data to its subscribers through
# App.QueueManager. Both failed in the field (DentaTec, 18.09. to 28.09.):
#   * a tab whose push stopped arriving (sleeping Edge tab, a second tab taking
#     the session over, a dropped socket) kept old numbers for as long as it
#     stayed open;
#   * a successful count request after a logout/login (200, full payload in the
#     server log) still left the board without numbers, because the delivery
#     path in between is shared with every other subscriber and never rebuilt
#     on login.
#
# The rules here:
#   * The server is asked directly (GET /ticket_overviews, computed on demand
#     per request, not from any websocket cache) on start, after login, after a
#     websocket (re)login, when the tab becomes visible or gets focus, when a VM
#     screen is shown, after a ticket is closed there, and every minute while a
#     VM screen is on screen.
#   * A websocket push is only a hint to ask again sooner. Its numbers are not
#     used: between full recomputes the server's push can carry an overview's
#     count from up to a minute earlier.
#   * One request at a time. A request asked for while one is running is not
#     dropped: it runs as soon as the first one returns, so a refresh after
#     "Erledigt & weiter" can never be answered by an older response.
#   * Failures retry with backoff and then keep polling. Subscribers always get
#     a state they can render: unknown (still loading), failed (could not load,
#     retrying) or the counts. Never an empty spot that looks like "no tickets".
#   * A category whose ticket list was just loaded takes its count from that
#     same response (setFromList), so the number next to an open queue is the
#     length of that queue.
#
# Source: GET /vm_counts (VmCountsController). Per overview it returns the
# total (the same number GET /ticket_overviews reports), how many of those are
# owned by the agent and how many by nobody, plus the agent's "Nur meine
# Tickets" choice. That choice lives here too, so the board, the workspace bar
# and the queue filter are one switch, stored server side in the agent's
# preferences (vm_only_mine) and therefore the same on every device.
#
# It also carries `introSeen`: whether the one-time hint pointing at the
# "Meine Tickets" tile and this switch has already been shown and dismissed
# (preference vm_intro_seen, same server-side/per-device storage as the
# switch). The server also treats an agent who already has a stored
# `vm_only_mine` choice as having seen it -- see VmCountsController.
class App.VmCounts
  @RETRY_MS:    [2000, 5000, 15000, 30000]
  @POLL_MS:     60000
  @THROTTLE_MS: 5000
  @TIMEOUT_MS:  20000

  @counts:   null     # { link: count } once known, null while unknown
  @mine:     {}       # { link: tickets owned by the current agent }
  @unassigned: {}     # { link: tickets owned by nobody }
  @onlyMine: false
  @onlyMineChosen: false
  @introSeen: null    # null while unknown, else the server's boolean
  @introPending: false
  @prefVersion: 0     # bumped on every local switch change
  @prefPending: false
  @failed:   false
  @source:   null     # 'server', 'list' or null: who set the last value
  @subs:     {}
  @subId:    0
  @inflight: false
  @again:    false
  @attempt:  0
  @retryTimer: null
  @pushTimer:  null
  @deferTimer: null
  @lastStart:  0
  @started:    false

  @subscribe: (callback) ->
    @start()
    @subId += 1
    id = @subId
    @subs[id] = callback
    @safeCall(callback)
    @refresh('subscribe') if !@counts and !@inflight
    id

  @unsubscribe: (id) ->
    delete @subs[id]

  @state: ->
    counts:          @counts
    mine:            @mine
    unassigned:      @unassigned
    onlyMine:        @onlyMine
    onlyMineChosen:  @onlyMineChosen
    introSeen:       @introSeen
    failed:          @failed
    source:          @source

  @start: ->
    return if @started
    @started = true

    App.Event.bind('ticket_overview_index', =>
      clearTimeout(@pushTimer)
      @pushTimer = setTimeout((=> @refresh('push')), 500)
    )
    App.Event.bind('ws:login', => @refresh('ws'))
    App.Event.bind('auth:logout', => @reset())
    App.Event.bind('auth:login', =>
      @reset()
      @refresh('login')
    )

    $(document).on('visibilitychange.vmCounts', =>
      @maybe() if document.visibilityState is 'visible'
    )
    $(window).on('focus.vmCounts', => @maybe())
    setInterval((=> @maybe()), @POLL_MS)

  # Throttled: visibility, focus and the minute poll. A trigger inside the
  # throttle window is deferred to its end, not dropped: the request that
  # started a moment ago may have been answered before the change the agent
  # is now looking for.
  @maybe: ->
    return if document.visibilityState is 'hidden'
    return if !@screenVisible()
    wait = @THROTTLE_MS - (Date.now() - @lastStart)
    if wait > 0
      @deferTimer ?= setTimeout((=>
        @deferTimer = null
        @maybe()
      ), wait)
      return
    @refresh('poll')

  @screenVisible: ->
    $('.vm-agent-tiles:visible, .vm-work:visible').length > 0

  @reset: ->
    @counts  = null
    @mine    = {}
    @unassigned = {}
    @onlyMine = false
    @onlyMineChosen = false
    @introSeen = null
    @introPending = false
    @prefPending = false
    @prefVersion += 1
    @failed  = false
    @source  = null
    @attempt = 0
    @again   = false
    clearTimeout(@retryTimer)
    @retryTimer = null
    @notify()

  @refresh: (reason) ->
    return if !App.Session.get('id')
    if @inflight
      @again = true
      return
    clearTimeout(@retryTimer)
    @retryTimer = null
    @inflight   = true
    @lastStart  = Date.now()
    prefVersion = @prefVersion
    App.Ajax.request(
      id:      'vm-counts'
      type:    'GET'
      url:     "#{App.Config.get('api_path')}/vm_counts"
      timeout: @TIMEOUT_MS
      processData: true
      # A background refresh must never pop up an error dialog, e.g. while
      # the server restarts during a deploy. Failures are shown on the badge.
      failResponseNoTrigger: true
      success: (data) =>
        @inflight = false
        if data and _.isArray(data.counts)
          counts = {}
          mine = {}
          unassigned = {}
          for row in data.counts when row and row.link
            counts[row.link]     = row.count
            mine[row.link]       = row.mine
            unassigned[row.link] = row.unassigned
          @counts  = counts
          @mine    = mine
          @unassigned = unassigned
          # A switch change made while this request was running wins over the
          # value the server read before that change was stored.
          if prefVersion is @prefVersion and !@prefPending
            @onlyMine       = !!data.only_mine
            @onlyMineChosen = !!data.only_mine_chosen
          # Same rule for the intro hint: a dismiss made while this request
          # was running must not be overwritten by the older server value.
          @introSeen = !!data.intro_seen if !@introPending
          @failed  = false
          @source  = 'server'
          @attempt = 0
          @notify()
        else
          @scheduleRetry()
        @runAgain()
      error: (xhr, status) =>
        @inflight = false
        # A logout aborts every request; nothing to retry without a session.
        return if !App.Session.get('id')
        @scheduleRetry()
        @runAgain()
    )

  @runAgain: ->
    return if !@again
    @again = false
    @refresh('again')

  @scheduleRetry: ->
    delay = @RETRY_MS[Math.min(@attempt, @RETRY_MS.length - 1)]
    @attempt += 1
    if @attempt >= @RETRY_MS.length and !@failed
      @failed = true
      @notify()
    clearTimeout(@retryTimer)
    @retryTimer = setTimeout((=> @refresh('retry')), delay)

  # The workspace just received the ticket list of one category. Its count
  # comes with that list from the same query, so it is the truest number for
  # that category right now.
  #
  # `mine`/`unassigned` are only passed when the list is complete (not cut at
  # the per-overview limit), because they are counted from its tickets.
  @setFromList: (link, count, mine, unassigned) ->
    return if !link or !_.isNumber(count)
    # Until the server's full set has arrived the other badges show the
    # loading marker; one known key must not turn them into empty spots.
    return if !@counts
    same = @counts[link] is count and
      (!_.isNumber(mine) or @mine[link] is mine) and
      (!_.isNumber(unassigned) or @unassigned[link] is unassigned)
    return if same
    counts = _.extend({}, @counts)
    counts[link] = count
    @counts = counts
    if _.isNumber(mine)
      @mine = _.extend({}, @mine)
      @mine[link] = mine
    if _.isNumber(unassigned)
      @unassigned = _.extend({}, @unassigned)
      @unassigned[link] = unassigned
    @failed = false
    @source = 'list'
    @notify()

  # The "Nur meine Tickets" switch. Shown at once, stored in the agent's
  # preferences (so it follows them to every device and survives a logout),
  # and put back with a message if the server refuses it.
  @setOnlyMine: (value) ->
    value = !!value
    return if value is @onlyMine and @onlyMineChosen
    previous = @onlyMine
    @onlyMine       = value
    @onlyMineChosen = true
    @prefPending    = true
    @prefVersion   += 1
    version = @prefVersion
    @notify()
    App.Ajax.request(
      id:          'vm-only-mine'
      type:        'PUT'
      url:         "#{App.Config.get('api_path')}/users/preferences"
      data:        JSON.stringify(vm_only_mine: value)
      processData: true
      failResponseNoTrigger: true
      success: =>
        return if version isnt @prefVersion
        @prefPending = false
        @refresh('switch')
      error: =>
        return if version isnt @prefVersion
        @prefPending = false
        @onlyMine    = previous
        @notify()
        App.Event.trigger('notify', type: 'error', msg: __('Die Einstellung konnte nicht gespeichert werden.'))
    )

  # The one-time hint for the "Meine Tickets" tile and the switch. Dismissed
  # once, from the hint's own close/"Verstanden" control, or implicitly as
  # soon as the agent turns out to already have a stored switch choice (see
  # `shouldShowIntro`) -- either way it is stored server side so it never
  # comes back, on this device or any other.
  @markIntroSeen: ->
    return if @introSeen or @introPending
    @introSeen    = true
    @introPending = true
    @notify()
    App.Ajax.request(
      id:          'vm-intro-seen'
      type:        'PUT'
      url:         "#{App.Config.get('api_path')}/users/preferences"
      data:        JSON.stringify(vm_intro_seen: true)
      processData: true
      failResponseNoTrigger: true
      success: => @introPending = false
      # Not persisted is not worth bothering the agent about; worst case the
      # hint shows again next time, which is harmless.
      error:   => @introPending = false
    )

  # Show the hint once we know for certain (not while still loading) that
  # this agent has neither dismissed it nor already made their own switch
  # choice -- someone who has already used the switch does not need to be
  # told how it works.
  @shouldShowIntro: (state) ->
    state.introSeen is false and !state.onlyMineChosen

  @notify: ->
    for id, callback of @subs
      @safeCall(callback)

  # What the badge for `link` shows, for the tiles and the workspace bar alike.
  # null only when this agent has no such overview at all.
  @badge: (state, link) ->
    return { kind: 'failed' } if !state.counts and state.failed
    return { kind: 'loading' } if !state.counts
    total = state.counts[link]
    return null if !_.isNumber(total)
    unassigned = state.unassigned[link]
    unassigned = 0 if !_.isNumber(unassigned)
    value = total
    value = state.mine[link] if state.onlyMine and _.isNumber(state.mine[link])
    {
      kind:       'count'
      value:      value
      total:      total
      hidden:     total - value
      unassigned: if value is total then 0 else Math.min(unassigned, total - value)
      stale:      !!state.failed
    }

  # "N weitere Tickets ausgeblendet, ..." for the switch, from the overview of
  # all open tickets (every category's tickets are in it exactly once).
  @hiddenSummary: (state, allLink = 'alle-ungel-sten-tickets') ->
    return null if !state.onlyMine or !state.counts
    b = @badge(state, allLink)
    return null if !b or b.kind isnt 'count'
    b

  # One broken subscriber must never stop the others from getting counts.
  @safeCall: (callback) ->
    try
      callback(@state())
    catch e
      console.error('App.VmCounts subscriber failed', e)
