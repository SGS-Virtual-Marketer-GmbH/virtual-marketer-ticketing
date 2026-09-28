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
class App.VmCounts
  @RETRY_MS:    [2000, 5000, 15000, 30000]
  @POLL_MS:     60000
  @THROTTLE_MS: 5000
  @TIMEOUT_MS:  20000

  @counts:   null     # { link: count } once known, null while unknown
  @failed:   false
  @source:   null     # 'server', 'list' or null: who set the last value
  @subs:     {}
  @subId:    0
  @inflight: false
  @again:    false
  @attempt:  0
  @retryTimer: null
  @pushTimer:  null
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
    counts: @counts
    failed: @failed
    source: @source

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

  # Throttled: visibility, focus and the minute poll.
  @maybe: ->
    return if document.visibilityState is 'hidden'
    return if !@screenVisible()
    return if Date.now() - @lastStart < @THROTTLE_MS
    @refresh('poll')

  @screenVisible: ->
    $('.vm-agent-tiles:visible, .vm-work:visible').length > 0

  @reset: ->
    @counts  = null
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
    App.Ajax.request(
      id:      'vm-counts'
      type:    'GET'
      url:     "#{App.Config.get('api_path')}/ticket_overviews"
      timeout: @TIMEOUT_MS
      processData: true
      # A background refresh must never pop up an error dialog, e.g. while
      # the server restarts during a deploy. Failures are shown on the badge.
      failResponseNoTrigger: true
      success: (data) =>
        @inflight = false
        if _.isArray(data)
          counts = {}
          counts[row.link] = row.count for row in data when row and row.link
          @counts  = counts
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
  @setFromList: (link, count) ->
    return if !link or !_.isNumber(count)
    # Until the server's full set has arrived the other badges show the
    # loading marker; one known key must not turn them into empty spots.
    return if !@counts
    return if @counts and @counts[link] is count
    counts = _.extend({}, @counts or {})
    counts[link] = count
    @counts = counts
    @failed = false
    @source = 'list'
    @notify()

  @notify: ->
    for id, callback of @subs
      @safeCall(callback)

  # One broken subscriber must never stop the others from getting counts.
  @safeCall: (callback) ->
    try
      callback(@state())
    catch e
      console.error('App.VmCounts subscriber failed', e)
