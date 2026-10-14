# Renders the aggregated customer profile from
# GET /vm_assistant/customer_profile — see VmAssistantController for the
# identity/signing side, and denta-care-agent's src/assistant/customerProfile.js
# for exactly what is (and honestly is not) computed. In particular: the order
# VALUE shown here is only ever a sum of the fetched page of orders, and the
# card always shows the exact label the backend sends for it rather than
# assuming it's a lifetime total.
#
# Nothing here asserts who the agent is or which ticket this is beyond the
# ticket number — the server takes the agent's identity from the session (see
# VmAssistantController#customer_profile) exactly like the assistant chat.

class App.VmCustomerProfile extends App.Controller
  events:
    'click .js-historyLockedToggle': 'toggleHelp'

  # A ticket in an area the agent may not open: the click explains why and who
  # to ask, instead of leading to an error page.
  toggleHelp: (e) =>
    e.preventDefault()
    $(e.currentTarget).closest('.js-historyLocked').find('.js-historyHelp').toggleClass('hide')

  constructor: (params) ->
    super
    @ticketNumber = params.ticketNumber
    @customerId   = params.customerId
    @history      = null
    @lastData     = null
    @lastError    = null
    @render(loading: true)
    @load()
    @loadHistory()

  render: (state = {}) =>
    @html App.view('vm_customer_profile')(
      loading: !!state.loading
      error:   state.error
      data:    state.data
      history: @history
    )

  # Every ticket of this customer in every area, as a timeline. Zammad's own
  # lists hide tickets in areas the agent cannot read; here they show up with
  # date, area, state and channel, but without title or content and without a
  # link (see VmCustomerHistoryController). A failed fetch just leaves the
  # section out: the profile above must not depend on it.
  loadHistory: =>
    return if !@customerId
    @ajax(
      id:   'vm-customer-history'
      type: 'GET'
      url:  "#{@apiPath}/vm_customer_history?customer_id=#{encodeURIComponent(@customerId)}"
      success: (data) =>
        @history = data
        @render(loading: !@lastData and !@lastError, data: @lastData, error: @lastError)
      error: =>
        @history = null
    )

  load: =>
    @ajax(
      id:   'vm-customer-profile'
      type: 'GET'
      url:  "#{@apiPath}/vm_assistant/customer_profile?ticket_number=#{encodeURIComponent(@ticketNumber)}"
      success: (data) =>
        if data.error
          @lastError = data.error
          @render(error: data.error)
          return
        @lastData = data
        @render(data: data)
      error: (xhr) =>
        message = switch xhr.status
          when 403 then __('Für diese Aktion fehlen dir die Rechte.')
          when 502, 503 then __('Gerade nicht erreichbar. Versuch es gleich noch einmal.')
          else __('Die Anfrage ist fehlgeschlagen.')
        @lastError = message
        @render(error: message)
    )
