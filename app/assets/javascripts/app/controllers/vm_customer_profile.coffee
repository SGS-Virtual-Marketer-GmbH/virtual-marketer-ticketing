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
  constructor: (params) ->
    super
    @ticketNumber = params.ticketNumber
    @render(loading: true)
    @load()

  render: (state = {}) =>
    @html App.view('vm_customer_profile')(
      loading: !!state.loading
      error:   state.error
      data:    state.data
    )

  load: =>
    @ajax(
      id:   'vm-customer-profile'
      type: 'GET'
      url:  "#{@apiPath}/vm_assistant/customer_profile?ticket_number=#{encodeURIComponent(@ticketNumber)}"
      success: (data) =>
        if data.error
          @render(error: data.error)
          return
        @render(data: data)
      error: (xhr) =>
        message = switch xhr.status
          when 403 then __('Für diese Aktion fehlen dir die Rechte.')
          when 502, 503 then __('Gerade nicht erreichbar. Versuch es gleich noch einmal.')
          else __('Die Anfrage ist fehlgeschlagen.')
        @render(error: message)
    )
