# The assistant panel.
#
# A slide-in chat, reachable from the dashboard board and from inside a ticket.
# Opened from a ticket it knows which one, so "fasse das zusammen" works without
# the agent retyping the number.
#
# The conversation is held here and sent back in full each turn. That keeps the
# service stateless — Cloud Run may route the next message to a different
# instance, and a restart must not lose somebody's chat.
#
# Nothing in here asserts who the user is. The server takes that from the
# session; see VMAssistantController.

class App.VmAssistant extends App.Controller
  elements:
    '.js-vmChatLog':   'log'
    '.js-vmChatInput': 'input'
    '.js-vmChatSend':  'sendButton'

  events:
    'submit .js-vmChatForm': 'submit'
    'click .js-vmSuggestion': 'useSuggestion'
    'keydown .js-vmChatInput': 'keydown'
    'click .js-vmReplyApply': 'replyApply'
    'click .js-vmReplySend':  'replySend'
    'click .js-vmReplyCopy':  'replyCopy'

  # Openers, so somebody staring at an empty box has somewhere to start.
  @SUGGESTIONS_TICKET: [
    __('Fasse dieses Ticket zusammen.')
    __('Was hat die KI hier schon herausgefunden?')
    __('Entwirf eine Antwort an den Kunden.')
  ]
  @SUGGESTIONS_GENERAL: [
    __('Welche Tickets sind mir zugewiesen?')
    __('Zeig mir offene Lieferungs-Tickets.')
    __('Welche Tickets hat noch niemand übernommen?')
  ]

  # Options from the host: ticketNumber, ticketId (the ticket open in the zoom),
  # inZoom (true in the ticket sidebar, where a reply box is on screen).
  constructor: ->
    super
    @history = []
    @busy    = false
    @render()

  render: =>
    @html App.view('vm_assistant')(
      ticketNumber: @ticketNumber
      suggestions:  if @ticketNumber then App.VmAssistant.SUGGESTIONS_TICKET else App.VmAssistant.SUGGESTIONS_GENERAL
    )
    @input.focus()

  # Point the panel at a different ticket, used by the workspace when someone
  # steps through the queue.
  #
  # The conversation is dropped, not carried over. It is sent back to the model
  # in full each turn, so keeping it would mean answering questions about ticket
  # B while still holding the customer data of ticket A — the model would mix
  # them, and confidently.
  setTicket: (number, id) =>
    return if number is @ticketNumber
    @ticketNumber = number
    @ticketId     = id
    @history      = []
    @busy         = false
    @render()

  keydown: (e) =>
    # Enter sends, Shift+Enter makes a new line — the convention everywhere
    # else people type messages.
    return if e.keyCode isnt 13 or e.shiftKey
    e.preventDefault()
    @submit(e)

  submit: (e) =>
    e.preventDefault() if e
    return if @busy
    message = @input.val().trim()
    return if !message

    @input.val('')
    # Once a real conversation is under way the intro disclaimer and the
    # opening suggestions are just clutter above it — they don't disappear on
    # their own, so every reply pushes the log further into a small scrollable
    # box. Hide them the moment the first message goes out.
    @$('.vm-chat__intro').addClass('hidden')
    @append('user', message)
    @setBusy(true)
    @ask(message)

  useSuggestion: (e) =>
    e.preventDefault()
    @input.val($(e.currentTarget).text().trim())
    @submit()

  ask: (message) =>
    @ajax(
      id:          'vm-assistant-chat'
      type:        'POST'
      url:         "#{@apiPath}/vm_assistant/chat"
      processData: true
      data:        JSON.stringify(
        message:       message
        history:       @history
        ticket_number: @ticketNumber
      )
      success: (data) =>
        @setBusy(false)
        if data.error
          @append('error', data.error)
          return
        @history = data.history or @history
        @append('assistant', data.antwort, data.aktionen, @replyFrom(data.aktionen))
      error: (xhr) =>
        @setBusy(false)
        # Say which kind of failure it was. "Etwas ist schiefgelaufen" sends
        # people to support for something they could have retried themselves.
        message = switch xhr.status
          when 403 then __('Für diese Aktion fehlen dir die Rechte.')
          when 502, 503 then __('Der Assistent ist gerade nicht erreichbar. Versuch es gleich noch einmal.')
          else __('Die Anfrage ist fehlgeschlagen.')
        @append('error', message)
    )

  setBusy: (state) =>
    @busy = state
    @sendButton.prop('disabled', state)
    @input.prop('disabled', state)
    @$('.js-vmChatThinking').toggleClass('hidden', !state)
    @scroll()
    @input.focus() if !state

  # `aktionen` is what the assistant actually did — shown so a note appearing on
  # a ticket is never a surprise, and so a wrong step is visible rather than
  # buried in prose.
  append: (role, text, actions, reply) =>
    # With a draft card the prose must not repeat the draft: the model likes to
    # quote it with "> ", and those markers then travel along when the text is
    # copied. Quoted lines are dropped from the prose; the card carries the text.
    text = String(text or '').split('\n').filter((l) -> !/^\s*>/.test(l)).join('\n').trim() if reply
    el = $(App.view('vm_assistant_message')(
      role:    role
      html:    if text then @formatMessage(text) else ''
      reply:   reply
      actions: ({ label: a.werkzeug.replace(/_/g, ' '), failed: !!(a.ergebnis and a.ergebnis.fehler) } for a in actions or [])
    ))
    @log.append(el)
    @loadReplyContext(el.find('.js-vmReply')) if reply
    @scroll()

  # The newest draft of this turn, if the assistant made one.
  replyFrom: (actions) =>
    drafts = (a for a in actions or [] when a.werkzeug is 'antwort_vorschlagen' and a.ergebnis?.entwurf and a.ergebnis?.ticketId)
    return null if !drafts.length
    last = drafts[drafts.length - 1].ergebnis
    { text: last.entwurf, ticketId: last.ticketId }

  # --- reply card -------------------------------------------------------------

  # Show where the reply would go before anybody can press anything, and only
  # enable the buttons for tickets that have an email channel.
  loadReplyContext: (card) =>
    meta = card.find('.js-vmReplyMeta')
    App.VmReplyHelper.context(card.data('ticket-id'), (error, context) =>
      if error or !context
        meta.text(__('Das Ticket konnte nicht geladen werden. Du kannst den Text trotzdem kopieren.'))
        return
      card.data('context', context)
      if !context.canMail
        meta.text(__('Dieses Ticket hat keinen E-Mail-Kanal. Du kannst den Text kopieren und im passenden Kanal einfügen.'))
        return
      meta.text("#{__('An')}: #{context.to}  ·  #{__('Betreff')}: #{context.subject}  ·  #{__('Ticket')} ##{context.number}")
      card.find('.js-vmReplyApply, .js-vmReplySend').prop('disabled', false)
      card.find('.js-vmReplyApply').text(if @canFillReplyBox(context) then __('In Antwortfeld übernehmen') else __('Als Entwurf ins Ticket'))
    )

  # Only the ticket open in the zoom has a reply box on screen.
  canFillReplyBox: (context) =>
    @inZoom and @ticketId and "#{@ticketId}" is "#{context.ticket.id}"

  replyStatus: (card, text, failed = false) =>
    card.find('.js-vmReplyStatus').text(text).toggleClass('vm-reply__status--failed', failed)

  replyApply: (e) =>
    e.preventDefault()
    card    = $(e.currentTarget).closest('.js-vmReply')
    context = card.data('context')
    text    = card.find('.js-vmReplyText').val()
    return if !context or !text.trim() or card.data('done')

    if @canFillReplyBox(context)
      App.VmReplyHelper.fillReplyBox(context, text)
      @replyStatus(card, __('Übernommen. Du findest den Text im Antwortfeld des Tickets, dort prüfen und senden.'))
      $('.ticketZoom .article-add').get(0)?.scrollIntoView?({ behavior: 'smooth', block: 'center' })
      return

    $(e.currentTarget).prop('disabled', true)
    App.VmReplyHelper.saveDraft(context, text, (error) =>
      $(e.currentTarget).prop('disabled', false)
      if error is 'exists'
        @replyStatus(card, __('Zu diesem Ticket gibt es schon einen Entwurf, von einer Kollegin, einem Kollegen oder von Virtual Marketer. Er wurde nicht überschrieben. Öffne das Ticket, dort kannst du den vorhandenen Entwurf übernehmen oder den Text von hand einfügen.'), true)
        return
      if error
        @replyStatus(card, __('Der Entwurf konnte nicht gespeichert werden.'), true)
        return
      @replyStatus(card, __('Als Entwurf im Ticket gespeichert. Im Ticket erscheint über dem Antwortfeld "Antwortvorschlag liegt bereit" mit der Schaltfläche "Einfügen".'))
      @navigate("#ticket/zoom/#{context.ticket.id}")
    )

  # Two clicks on purpose: the first arms the button and names the recipient,
  # the second sends. A mail to a customer cannot be taken back.
  replySend: (e) =>
    e.preventDefault()
    button  = $(e.currentTarget)
    card    = button.closest('.js-vmReply')
    context = card.data('context')
    text    = card.find('.js-vmReplyText').val()
    return if !context or !context.canMail or !text.trim() or card.data('done')

    if !button.data('armed')
      button.data('armed', true).data('armedAt', Date.now()).addClass('vm-reply__btn--armed')
      button.text("#{__('Ja, jetzt an')} #{context.to} #{__('senden')}")
      clearTimeout(button.data('timer'))
      button.data('timer', setTimeout(=>
        button.data('armed', false).removeClass('vm-reply__btn--armed').text(__('Senden'))
      , 8000))
      return

    # A double click arms and sends in one go and the recipient is never read.
    return if Date.now() - (button.data('armedAt') or 0) < 700

    clearTimeout(button.data('timer'))
    card.data('done', true)
    card.find('button').prop('disabled', true)
    @replyStatus(card, __('Wird gesendet …'))
    App.VmReplyHelper.send(context, text, (error, detail) =>
      if error
        card.data('done', false)
        card.find('button').prop('disabled', false)
        button.data('armed', false).removeClass('vm-reply__btn--armed').text(__('Senden'))
        message =
          if error is 403
            __('Dafür fehlen dir die Rechte an diesem Ticket.')
          else if /no email address/i.test(String(detail or ''))
            __('Die Gruppe dieses Tickets hat keine Absenderadresse. Bitte im Admin-Bereich eine E-Mail-Adresse für die Gruppe hinterlegen. Es wurde nichts verschickt.')
          else
            __('Die Antwort konnte nicht gesendet werden. Es wurde nichts verschickt.')
        @replyStatus(card, message, true)
        return
      App.VmReplyHelper.claimIfUnowned(context)
      card.find('.js-vmReplyText').prop('readonly', true)
      card.find('.js-vmReplyCopy').prop('disabled', false)
      button.text(__('Gesendet'))
      @replyStatus(card, "#{__('Gesendet an')} #{context.to}.")
    )

  # Plain text from the textarea: no quote markers, nothing to clean up after.
  replyCopy: (e) =>
    e.preventDefault()
    card = $(e.currentTarget).closest('.js-vmReply')
    text = card.find('.js-vmReplyText').val()
    done = => @replyStatus(card, __('Text kopiert.'))
    if navigator.clipboard?.writeText
      navigator.clipboard.writeText(text).then(done, -> card.find('.js-vmReplyText').select())
    else
      card.find('.js-vmReplyText').select()
      document.execCommand?('copy')
      done()

  # Escape first, THEN linkify. The other order would let a message containing
  # markup have that markup turned into a live link — and the model's answers
  # quote customer text verbatim, so the input is not trustworthy.
  #
  # Links matter enough to be worth doing at all: the whole point of the Xentral
  # deep links is that an agent gets to the order with one click.
  #
  # A question like "welche Tickets sind mir zugewiesen" naturally comes back
  # as a Markdown list ("- **#2264**: ..."). Left as plain text that renders as
  # literal asterisks and dashes — worse than no formatting at all. The two
  # constructs the model actually reaches for, bold and "- " bullets, are
  # turned into real HTML; anything else is left as escaped text.
  formatMessage: (text) ->
    escaped = String(text or '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')

    linked = escaped.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>')
    bold   = linked.replace(/\*\*([^\n*]+)\*\*/g, '<strong>$1</strong>')

    html  = ''
    items = null
    flushList = ->
      return if !items
      itemsHtml = ("<li>#{i}</li>" for i in items).join('')
      html += "<ul>#{itemsHtml}</ul>"
      items = null
    for line in bold.split('\n')
      match = line.match(/^[-*]\s+(.*)$/)
      if match
        items ?= []
        items.push(match[1])
      else
        flushList()
        html += (if html then '<br>' else '') + line
    flushList()
    html

  scroll: =>
    @log.scrollTop(@log[0].scrollHeight) if @log[0]

App.Config.set('VmAssistant', { controller: 'VmAssistant' }, 'Assistant')
