# The workspace: one screen for working a category start to finish.
#
# Categories across the top, the queue on the left, the ticket in the middle,
# the assistant on the right. Arrow keys or the ‹ › buttons walk the queue. The
# point is that reading a ticket, seeing what the pipeline already found, and
# asking the assistant about it happen without changing screens.
#
# Two boundaries this deliberately does NOT cross:
#
#   1. No mail composer. Replying to a customer stays in the real ticket zoom,
#      which has the signature, attachment and recipient handling this screen
#      would have to reimplement — and getting any of that subtly wrong sends a
#      wrong mail to a real customer. "Antworten" opens the ticket; the drafted
#      reply travels via the clipboard.
#
#   2. The assistant works the open ticket and only when asked. Nothing runs in
#      the background, so no ticket is ever touched because somebody scrolled
#      past it.
#
# Everything here goes through the normal API as the logged-in agent, so the
# queue, the ticket and every action are already bounded by their group
# permissions — a ticket they may not see never arrives.

class App.VmWorkspace extends App.Controller
  elements:
    '.js-vmQueue':      'queueEl'
    '.js-vmTicket':     'ticketEl'
    '.js-vmFound':      'foundEl'
    '.js-vmAssistant':  'assistantEl'
    '.js-vmPos':        'posEl'

  events:
    'click .js-vmCat':      'chooseCategory'
    'click .js-vmQueueItem':'chooseTicketFromQueue'
    'click .js-vmPrev':     'previous'
    'click .js-vmNext':     'next'
    'click .js-vmOpen':     'openTicket'
    'click .js-vmNote':     'openTicket'
    'click .js-vmDone':     'closeAndAdvance'
    'click .js-vmCopyDraft':'copyDraft'
    'click .js-vmBack':     'backToBoard'
    'change .js-vmMine':    'toggleMine'
    'click .js-vmQuoteToggle': 'toggleQuote'

  constructor: (params) ->
    super
    @category  = params.category or App.VmWorkspace.categories()[0]?.key
    @ticketId  = if params.ticketId then parseInt(params.ticketId, 10) else null
    @tickets   = []
    @articles  = []
    @note      = null
    @countState = App.VmCounts.state()
    @listCount = null
    @listAt    = 0
    @onlyMine  = !!@countState.onlyMine
    @loading   = true
    @presence  = {}
    @render()
    @countsSubId = App.VmCounts.subscribe(@updateCounts)
    App.VmCounts.refresh('workspace')
    @bindQueue()
    @bindKeys()
    # Who else has a queue ticket open: asked for the whole list at once, every
    # 30 seconds, and again whenever the list itself changes.
    @presenceIntervalId = @interval(@refreshPresence, 30000, 'vm-workspace-presence')
    # The push for this queue is only a hint to ask the server sooner. The
    # list itself always comes from our own request (refreshData).
    @controllerBind('ticket_overview_list', (data) =>
      return if data?.overview?.view isnt @category
      App.Delay.set(@refreshData, 500, 'vm-workspace-list-push')
    )

  # The categories are the tile board's, so both screens always agree on what
  # exists and what it is called.
  @categories: -> App.VmAgentTiles?.TILES or []

  release: =>
    $(document).off('keydown.vmWorkspace')
    App.VmCounts.unsubscribe(@countsSubId) if @countsSubId
    @clearInterval(@presenceIntervalId) if @presenceIntervalId

  # This task is persistent (see VmWorkspaceRouter below), so re-entering its
  # route -- from the tile board, a bookmark, or browser back/forward -- does
  # NOT get a new constructor call. TaskManager reuses this instance and calls
  # show() with the route's params instead. Without this, those params were
  # silently dropped and the screen kept showing whatever category/ticket was
  # already open, e.g. picking "Produktberatung" from the board while
  # "Stornos" was still the open workspace just reopened Stornos.
  #
  # Coming back to this screen is also exactly when its numbers are most likely
  # old (it sat hidden while others worked the queue), so every show() asks the
  # server again rather than replaying what the collections cached.
  show: (params = {}) =>
    return if !params.category
    ticketId = if params.ticketId then parseInt(params.ticketId, 10) else null
    App.VmCounts.refresh('show')
    if params.category is @category and ticketId is @ticketId
      @refreshData()
      return
    @category = params.category
    @ticketId = ticketId
    @note     = null
    @articles = []
    @render()
    @bindQueue()

  # The queue straight from the server, not from App.OverviewListCollection:
  # that collection hands results to its subscribers through App.QueueManager,
  # and one failing subscriber anywhere in the tab used to stop every later
  # result from arriving (see App.VmCounts). One request at a time; a refresh
  # asked for while one is running runs right after it, so the newest state
  # always wins.
  refreshData: =>
    return if !@category
    if @listInflight
      @listAgain = true
      return
    category      = @category
    @listInflight = true
    App.Ajax.request(
      id:          'vm-workspace-list'
      type:        'GET'
      url:         "#{@apiPath}/ticket_overviews"
      data:
        view: category
      processData: true
      failResponseNoTrigger: true
      success: (data) =>
        @listInflight = false
        if data?.assets
          App.Collection.loadAssets(data.assets)
          delete data.assets
        @updateQueue(data.index) if category is @category and data?.index
        @refreshAgain()
      error: =>
        @listInflight = false
        if category is @category and @loading
          App.Delay.set(@refreshData, 5000, 'vm-workspace-list-retry')
        @refreshAgain()
    )

  refreshAgain: =>
    return if !@listAgain
    @listAgain = false
    @refreshData()

  bindKeys: =>
    $(document).on('keydown.vmWorkspace', (e) =>
      return if @el.is(':hidden')
      # Never steal the arrow keys from someone typing — the assistant's input
      # lives on this same screen.
      return if $(e.target).is('input, textarea, select, [contenteditable]')
      if e.keyCode is 37
        e.preventDefault()
        @previous()
      else if e.keyCode is 39
        e.preventDefault()
        @next()
    )

  viewParams: =>
    categories: App.VmWorkspace.categories()
    category:     @category
    state:        @countState
    onlyMine:   @onlyMine

  render: =>
    # The assistant lives in a container this template rebuilds. Re-creating
    # the markup used to leave the assistant rendering into the old, detached
    # node, so its panel went blank after the first render. Carry its element
    # (with its conversation and event handlers) over into the new markup.
    assistantNode = @assistant?.el?.detach()
    @html App.view('vm_workspace')(@viewParams())
    if assistantNode
      @el.find('.js-vmAssistant').replaceWith(assistantNode)
      @refreshElements()
    @renderQueue()
    @renderTicket()

  renderQueue: =>
    return if !@queueEl
    @queueEl.html App.view('vm_workspace_queue')(
      tickets:  @visibleTickets()
      ticketId: @ticketId
      loading:  @loading
      onlyMine: @onlyMine
      hidden:   @hiddenInQueue()
      presence: @presence
      humanTime: (iso) -> App.VmWorkspace.humanTime(iso)
    )
    @renderPosition()

  # Small dot per queue row: a colleague has the ticket open (blue) or is
  # writing in it (orange). The same two levels as App.VmCollisionBanner, from
  # the same shared taskbar data, but asked for the whole queue in one request.
  # Silent on failure: the dot is a courtesy, never a reason to disturb work.
  refreshPresence: =>
    ids = (t.id for t in @visibleTickets())
    if ids.length is 0
      return if _.isEmpty(@presence)
      @presence = {}
      return @renderQueue()
    @ajax(
      id:          'vm-workspace-presence'
      type:        'GET'
      url:         "#{@apiPath}/vm_ticket_presence"
      data:        { ids: ids.join(',') }
      processData: true
      success: (data) =>
        next = data?.presence or {}
        return if JSON.stringify(next) is JSON.stringify(@presence)
        @presence = next
        @renderQueue()
    )

  # Tooltip text for the dot; names are escaped by the template (<%= %>).
  @presenceTitle: (people) ->
    return '' if !people?.length
    editing = _.filter(people, (p) -> p.editing)
    list    = if editing.length then editing else people
    names   = _.map(list, (p) -> p.name)
    who     = if names.length is 1 then names[0] else "#{names[...-1].join(', ')} und #{names[names.length - 1]}"
    many    = names.length > 1
    if editing.length
      "#{who} #{if many then 'schreiben' else 'schreibt'} gerade eine Antwort oder Notiz in diesem Ticket. Bitte kurz abstimmen, bevor du antwortest."
    else
      "#{who} #{if many then 'haben' else 'hat'} dieses Ticket gerade geöffnet."

  renderPosition: =>
    return if !@posEl
    list  = @visibleTickets()
    index = _.findIndex(list, (t) => t.id is @ticketId)
    @posEl.text(if index >= 0 then "#{index + 1} / #{list.length}" else "- / #{list.length}")

  renderTicket: =>
    return if !@ticketEl
    ticket = @currentTicket()
    @ticketEl.html App.view('vm_workspace_ticket')(
      ticket:   ticket
      articles: @articles
      note:     @note
      loading:  @loading
      humanTime: (iso) -> App.VmWorkspace.humanTime(iso)
      body:     (article) -> App.VmWorkspace.renderBody(article)
    )
    @collapseQuotes()
    @renderFound()
    @mountAssistant()

  # A reply to a notification email carries the whole notification back with
  # it — signature, disclaimer, the original table-laid-out HTML and all —
  # inside a <blockquote>, exactly like every mail client's own quoting.
  # Dumped in full, that buries the one or two sentences somebody actually
  # wrote under everything DentaTec already sent them. Zammad's own newer UI
  # collapses long article bodies behind a "show more" for the same reason
  # (useArticleToggleMore); this view has no equivalent, so it's added here,
  # scoped to the reliable part — a <blockquote> is how every mail client
  # marks quoted history, whatever product actually sent the original mail.
  collapseQuotes: =>
    return if !@ticketEl
    @ticketEl.find('.vm-work__msgbody').each (i, el) =>
      $el   = $(el)
      quote = $el.find('blockquote').first()
      return if !quote.length

      # If the quote IS the whole message, collapsing it would leave nothing
      # to read at all — worse than showing the quote.
      clone = $el.clone()
      clone.find('blockquote').remove()
      return if $.trim(clone.text()) is ''

      quote.addClass('vm-work__quote--collapsed')
      quote.before($('<button/>',
        type:  'button'
        class: 'vm-work__quotetoggle js-vmQuoteToggle'
        text:  "#{@T('Verlauf anzeigen')} ▾"
      ))

  toggleQuote: (e) =>
    e.preventDefault()
    btn   = $(e.currentTarget)
    quote = btn.next('blockquote')
    return if !quote.length
    collapsed = quote.toggleClass('vm-work__quote--collapsed').hasClass('vm-work__quote--collapsed')
    btn.text("#{if collapsed then @T('Verlauf anzeigen') else @T('Verlauf ausblenden')} #{if collapsed then '▾' else '▴'}")

  renderFound: =>
    return if !@foundEl
    @foundEl.html App.view('vm_workspace_found')(
      note:    @note
      sources: @note?.sources() or []
      links:   @note?.links() or []
      draft:   @note?.draft()
      voicemail: @note?.voicemail()
    )

  # One assistant instance for the whole screen. Re-creating it per ticket would
  # throw away the conversation on every arrow key; instead it is told which
  # ticket it is looking at, and it starts a fresh conversation for that ticket.
  mountAssistant: =>
    ticket = @currentTicket()
    return if !@assistantEl or !@assistantEl.length
    if !@assistant
      @assistant = new App.VmAssistant(
        el:           @assistantEl
        ticketNumber: ticket?.number
        ticketId:     ticket?.id
      )
    else
      @assistant.setTicket(ticket?.number, ticket?.id)

  # --- data ------------------------------------------------------------------

  # Counts come from App.VmCounts. When the server's number for the open
  # category no longer matches the queue on screen (a new ticket came in,
  # someone else closed one), or the queue is older than a few seconds, the
  # queue is fetched again, so the number and the list cannot stay apart.
  updateCounts: (state) =>
    @countState = state
    if !!state.onlyMine isnt @onlyMine
      @onlyMine = !!state.onlyMine
      @applyOnlyMine()
      return
    if state.source is 'server' and state.counts and !@el.is(':hidden')
      serverCount = state.counts[@category]
      if serverCount isnt @listCount or Date.now() - @listAt > 5000
        @refreshData()
    # Only the category bar shows counts. Re-rendering the whole screen on
    # every count change would also rebuild the queue and the open ticket.
    bar = @el.find('.vm-work__cats')
    return @render() if !bar.length
    bar.replaceWith($(App.view('vm_workspace')(@viewParams())).find('.vm-work__cats'))

  # Loads the queue of the current @category. Called on construction and
  # every time @category changes (chooseCategory, show()).
  bindQueue: =>
    @loading   = true
    @listCount = null
    @renderQueue()
    @refreshData()

  # `data` here is already the unwrapped `{overview, tickets, count}` shape —
  # asset loading happened inside the collection before this fires, for both
  # the initial fetch and every later push.
  updateQueue: (data) =>
    return if !data
    @loading   = false
    @listAt    = Date.now()
    @listCount = if _.isNumber(data.count) then data.count else (data.tickets or []).length
    ids = (row.id for row in (data.tickets or []))
    @tickets = (App.Ticket.find(id) for id in ids when App.Ticket.exists(id))
    # The count that came with this list is the count of this list.
    @pushListCounts()
    # Keep the ticket from the URL if it is in this queue, otherwise start at
    # the top. Silently jumping elsewhere would lose someone's place.
    if !@ticketId or !_.find(@visibleTickets(), (t) => t.id is @ticketId)
      @ticketId = @visibleTickets()[0]?.id or null
    @renderQueue()
    @refreshPresence()
    @fetchTicket()

  fetchTicket: =>
    if !@ticketId
      @articles = []
      @note     = null
      @renderTicket()
      return
    id = @ticketId
    @ajax(
      id:          'vm-workspace-articles'
      type:        'GET'
      url:         "#{@apiPath}/ticket_articles/by_ticket/#{id}"
      processData: true
      success: (data) =>
        # A slow response for a ticket the agent has already left must not
        # overwrite the one they are looking at now.
        return if id isnt @ticketId
        @articles = data or []
        @note     = App.VmPipelineNote.from(@articles)
        @renderTicket()
      error: =>
        return if id isnt @ticketId
        @articles = []
        @note     = null
        @renderTicket()
    )

  # --- state -----------------------------------------------------------------

  # Sorted by status signal (see App.VmSignal): what needs us first, what only
  # waits last. Inside one signal the server's order stays, and arrow keys, the
  # position counter and "Erledigt & weiter" all walk this same order.
  visibleTickets: =>
    list = @tickets
    if @onlyMine
      me = App.Session.get('id')
      list = (t for t in @tickets when t.owner_id is me)
    App.VmSignal.sort(list)

  currentTicket: =>
    _.find(@visibleTickets(), (t) => t.id is @ticketId) or null

  # --- actions ---------------------------------------------------------------

  chooseCategory: (e) =>
    e.preventDefault()
    key = $(e.currentTarget).data('key')
    return if !key or key is @category
    @category = key
    @ticketId = null
    @note     = null
    @articles = []
    @render()
    @bindQueue()
    @navigate "#vm_work/#{key}", { hideCurrentLocationFromHistory: true }

  chooseTicketFromQueue: (e) =>
    e.preventDefault()
    id = parseInt($(e.currentTarget).data('id'), 10)
    @select(id)

  select: (id) =>
    return if !id or id is @ticketId
    @ticketId = id
    @articles = []
    @note     = null
    @renderQueue()
    @renderTicket()
    @fetchTicket()
    @navigate "#vm_work/#{@category}/#{id}", { hideCurrentLocationFromHistory: true }

  step: (offset) =>
    list  = @visibleTickets()
    index = _.findIndex(list, (t) => t.id is @ticketId)
    return if index < 0
    target = list[index + offset]
    @select(target.id) if target

  previous: (e) =>
    e?.preventDefault()
    @step(-1)

  next: (e) =>
    e?.preventDefault()
    @step(1)

  # The queue's "Nur meine" switch is the board's "Nur meine Tickets" switch,
  # not a second filter: one stored choice for the tiles, the category bar and
  # every queue. The change comes back through updateCounts.
  toggleMine: (e) =>
    App.VmCounts.setOnlyMine($(e.currentTarget).prop('checked'))

  applyOnlyMine: =>
    if !_.find(@visibleTickets(), (t) => t.id is @ticketId)
      @ticketId = @visibleTickets()[0]?.id or null
      @articles = []
      @note     = null
      @fetchTicket()
    @render()

  # Mine and unassigned are counted from the list only when it is complete
  # (not cut at the per-overview ticket limit).
  pushListCounts: =>
    return if !_.isNumber(@listCount)
    if @tickets.length is @listCount
      me = App.Session.get('id')
      mine       = (t for t in @tickets when t.owner_id is me).length
      unassigned = (t for t in @tickets when !t.owner_id or t.owner_id is 1).length
      App.VmCounts.setFromList(@category, @listCount, mine, unassigned)
    else
      App.VmCounts.setFromList(@category, @listCount)

  # Tickets of this category the "mine" view leaves out, from the loaded list.
  hiddenInQueue: =>
    return null if !@onlyMine or @loading
    me = App.Session.get('id')
    others = (t for t in @tickets when t.owner_id isnt me)
    return null if !others.length
    {
      count:      others.length
      unassigned: (t for t in others when !t.owner_id or t.owner_id is 1).length
    }

  openTicket: (e) =>
    e.preventDefault()
    return if !@ticketId
    @navigate "#ticket/zoom/#{@ticketId}"

  backToBoard: (e) =>
    e.preventDefault()
    @navigate '#dashboard'

  # Closes the ticket and moves on in one step, which is the whole rhythm of
  # working a queue. The next ticket is picked BEFORE the request, so the queue
  # reordering underneath cannot land the agent somewhere unexpected.
  closeAndAdvance: (e) =>
    e.preventDefault()
    id = @ticketId
    return if !id
    list   = @visibleTickets()
    index  = _.findIndex(list, (t) => t.id is id)
    target = list[index + 1] or list[index - 1]
    state  = App.TicketState.findByAttribute('name', 'closed')
    return @notify(type: 'error', msg: __('Der Status "Erledigt" ist nicht eingerichtet.')) if !state

    @ajax(
      id:          "vm-workspace-close-#{id}"
      type:        'PUT'
      url:         "#{@apiPath}/tickets/#{id}"
      processData: true
      data:        JSON.stringify(state_id: state.id)
      success: =>
        before   = @tickets.length
        @tickets = (t for t in @tickets when t.id isnt id)
        if @listCount? and @tickets.length < before
          @listCount = Math.max(0, @listCount - 1)
          @pushListCounts()
        if target
          @ticketId = null
          @select(target.id)
        else
          @ticketId = null
          @renderQueue()
          @renderTicket()
        # Do not wait for the websocket push to correct the count: in a tab
        # whose push is not arriving (sleeping Edge tab, dropped socket) the
        # queue above is already empty while the count next to it would keep
        # the old number indefinitely. The PUT has committed by now; the short
        # delay only lets several quick closes share one refetch.
        App.Delay.set((-> App.VmCounts.refresh('close')), 300, 'vm-workspace-after-close')
      error: =>
        @notify(type: 'error', msg: __('Das Ticket konnte nicht geschlossen werden.'))
    )

  copyDraft: (e) =>
    e.preventDefault()
    draft = @note?.draft()
    return if !draft
    # The reply itself belongs in the ticket zoom, where the composer handles
    # signature, recipients and attachments. This just carries the text over.
    #
    # navigator.clipboard rather than the bare `clipboard` global used elsewhere
    # in this codebase: it is the standard API, and the helpdesk is served over
    # HTTPS, which is the secure context it requires. The textarea fallback
    # covers the case where the browser refuses the permission.
    done = => @notify(type: 'success', msg: __('Antwortvorschlag kopiert. Im Ticket einfügen und prüfen.'))
    failed = => @notify(type: 'error', msg: __('Kopieren nicht möglich. Bitte den Text markieren und selbst kopieren.'))

    if navigator.clipboard?.writeText
      navigator.clipboard.writeText(draft).then(done, => @copyViaTextarea(draft, done, failed))
    else
      @copyViaTextarea(draft, done, failed)

  copyViaTextarea: (text, done, failed) =>
    helper = $('<textarea>').val(text).css(position: 'fixed', top: '-1000px').appendTo('body')
    helper[0].select()
    try
      if document.execCommand('copy') then done() else failed()
    catch
      failed()
    helper.remove()

  # --- helpers ---------------------------------------------------------------

  @humanTime: (iso) ->
    return '' if !iso
    diff = (Date.now() - new Date(iso).getTime()) / 1000
    return App.i18n.translateContent('gerade eben') if diff < 90
    return "vor #{Math.round(diff / 60)} Min." if diff < 5400
    return "vor #{Math.round(diff / 3600)} Std." if diff < 172800
    "vor #{Math.round(diff / 86400)} Tg."

  # Article bodies are customer-authored. text/html has already been sanitised
  # by the server; anything else is escaped here and must never be inserted raw.
  @renderBody: (article) ->
    return article.body if article.content_type is 'text/html'
    String(article.body or '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/\n/g, '<br>')


class VmWorkspaceRouter extends App.ControllerPermanent
  @requiredPermission: 'ticket.agent'

  constructor: (params) ->
    super
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'VmWorkspace'
      controller: 'VmWorkspace'
      params:     params
      show:       true
      persistent: true
    )

App.Config.set('vm_work', VmWorkspaceRouter, 'Routes')
App.Config.set('vm_work/:category', VmWorkspaceRouter, 'Routes')
App.Config.set('vm_work/:category/:ticketId', VmWorkspaceRouter, 'Routes')
