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
    'click .js-vmChatClose': 'close'
    'click .js-vmSuggestion': 'useSuggestion'
    'keydown .js-vmChatInput': 'keydown'

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
        @append('assistant', data.antwort, data.aktionen)
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
  append: (role, text, actions) =>
    @log.append(App.view('vm_assistant_message')(
      role:    role
      html:    @formatMessage(text)
      actions: ({ label: a.werkzeug.replace(/_/g, ' '), failed: !!(a.ergebnis and a.ergebnis.fehler) } for a in actions or [])
    ))
    @scroll()

  # Escape first, THEN linkify. The other order would let a message containing
  # markup have that markup turned into a live link — and the model's answers
  # quote customer text verbatim, so the input is not trustworthy.
  #
  # Links matter enough to be worth doing at all: the whole point of the Xentral
  # deep links is that an agent gets to the order with one click.
  formatMessage: (text) ->
    escaped = String(text or '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
    escaped
      .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>')
      .replace(/\n/g, '<br>')

  scroll: =>
    @log.scrollTop(@log[0].scrollHeight) if @log[0]

  close: =>
    @el.trigger('vm-assistant:close')

App.Config.set('VmAssistant', { controller: 'VmAssistant' }, 'Assistant')
