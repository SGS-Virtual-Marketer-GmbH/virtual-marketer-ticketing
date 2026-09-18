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
    'click .js-vmMine':     'toggleMine'
    'click .js-vmQuoteToggle': 'toggleQuote'

  constructor: (params) ->
    super
    @category  = params.category or App.VmWorkspace.categories()[0]?.key
    @ticketId  = if params.ticketId then parseInt(params.ticketId, 10) else null
    @tickets   = []
    @articles  = []
    @note      = null
    @counts    = {}
    @onlyMine  = false
    @loading   = true
    @render()
    @countsBindId = App.OverviewIndexCollection.bind(@updateCounts)
    @bindQueue()
    @bindKeys()

  # The categories are the tile board's, so both screens always agree on what
  # exists and what it is called.
  @categories: -> App.VmAgentTiles?.TILES or []

  release: =>
    $(document).off('keydown.vmWorkspace')
    App.OverviewIndexCollection.unbindById(@countsBindId) if @countsBindId
    App.OverviewListCollection.unbind(@queueBindId) if @queueBindId

  # This task is persistent (see VmWorkspaceRouter below), so re-entering its
  # route -- from the tile board, a bookmark, or browser back/forward -- does
  # NOT get a new constructor call. TaskManager reuses this instance and calls
  # show() with the route's params instead. Without this, those params were
  # silently dropped and the screen kept showing whatever category/ticket was
  # already open, e.g. picking "Produktberatung" from the board while
  # "Stornos" was still the open workspace just reopened Stornos.
  show: (params = {}) =>
    return if !params.category
    ticketId = if params.ticketId then parseInt(params.ticketId, 10) else null
    return if params.category is @category and ticketId is @ticketId
    @category = params.category
    @ticketId = ticketId
    @note     = null
    @articles = []
    @render()
    @bindQueue()

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

  render: =>
    @html App.view('vm_workspace')(
      categories: App.VmWorkspace.categories()
      category:   @category
      counts:     @counts
      onlyMine:   @onlyMine
    )
    @renderQueue()
    @renderTicket()

  renderQueue: =>
    return if !@queueEl
    @queueEl.html App.view('vm_workspace_queue')(
      tickets:  @visibleTickets()
      ticketId: @ticketId
      loading:  @loading
      onlyMine: @onlyMine
      humanTime: (iso) -> App.VmWorkspace.humanTime(iso)
    )
    @renderPosition()

  renderPosition: =>
    return if !@posEl
    list  = @visibleTickets()
    index = _.findIndex(list, (t) => t.id is @ticketId)
    @posEl.text(if index >= 0 then "#{index + 1} / #{list.length}" else "— / #{list.length}")

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
      )
    else
      @assistant.setTicket(ticket?.number)

  # --- data ------------------------------------------------------------------

  # Both the category-bar counts and the queue below ride the same live feed
  # the native sidebar's overview counts use (App.OverviewIndexCollection /
  # App.OverviewListCollection — see navigation.coffee): the server recomputes
  # and pushes over the existing websocket whenever any ticket changes, so a
  # closed/reassigned ticket disappears here without a manual refresh, and the
  # tile board and this bar never disagree with what's actually behind them.

  updateCounts: (data) =>
    return if !_.isArray(data)
    @counts = {}
    @counts[row.link] = row.count for row in data
    @render()

  # Re-subscribes the queue to the current @category, dropping the previous
  # subscription first — called on construction and every time @category
  # changes (chooseCategory, show()).
  bindQueue: =>
    App.OverviewListCollection.unbind(@queueBindId) if @queueBindId
    @loading = true
    @renderQueue()
    @queueBindId = App.OverviewListCollection.bind(@category, @updateQueue)

  # `data` here is already the unwrapped `{overview, tickets, count}` shape —
  # asset loading happened inside the collection before this fires, for both
  # the initial fetch and every later push.
  updateQueue: (data) =>
    return if !data
    @loading = false
    ids = (row.id for row in (data.tickets or []))
    @tickets = (App.Ticket.find(id) for id in ids when App.Ticket.exists(id))
    # Keep the ticket from the URL if it is in this queue, otherwise start at
    # the top. Silently jumping elsewhere would lose someone's place.
    if !@ticketId or !_.find(@visibleTickets(), (t) => t.id is @ticketId)
      @ticketId = @visibleTickets()[0]?.id or null
    @renderQueue()
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

  visibleTickets: =>
    return @tickets if !@onlyMine
    me = App.Session.get('id')
    (t for t in @tickets when t.owner_id is me)

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

  toggleMine: (e) =>
    e.preventDefault()
    @onlyMine = !@onlyMine
    if !_.find(@visibleTickets(), (t) => t.id is @ticketId)
      @ticketId = @visibleTickets()[0]?.id or null
      @articles = []
      @note     = null
      @fetchTicket()
    @render()

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
        @tickets = (t for t in @tickets when t.id isnt id)
        if target
          @ticketId = null
          @select(target.id)
        else
          @ticketId = null
          @renderQueue()
          @renderTicket()
        # No manual refresh needed: closing the ticket changes its updated_at,
        # which the live feed above picks up on its own next push.
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
    done = => @notify(type: 'success', msg: __('Antwortvorschlag kopiert — im Ticket einfügen und prüfen.'))
    failed = => @notify(type: 'error', msg: __('Kopieren nicht möglich — bitte den Text markieren und selbst kopieren.'))

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
