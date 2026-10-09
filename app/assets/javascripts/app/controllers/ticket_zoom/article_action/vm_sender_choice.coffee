# Lets the agent pick which system address an email reply is sent from.
#
# Without this, a reply always leaves from the ticket group's own address. When
# the system has further active sender addresses, a "From" selector appears in
# the email reply box, the group's address preselected. With only one address
# nothing is rendered and nothing is sent, so the reply box and the request are
# exactly what they were before.
#
# The list comes from GET /vm_sender_addresses (VmSenderChoice on the server),
# not from App.EmailAddress: only the server knows whether an address's channel
# is active and able to send. The server checks the choice again when the
# article is created, so this selector is a convenience, not the safeguard.
#
# Hooks into the reply box through the same article-action config the other
# reply types use (setArticleTypePost / params), so article_new.coffee and its
# template stay untouched.
class VmSenderChoice
  @FIELD: 'vm_sender_email_address_id'

  # Not a per-article action; the framework calls these unguarded.
  @action: (actions, ticket, article, ui) -> actions
  @perform: (articleContainer, type, ticket, article, ui) -> true

  @setArticleTypePost: (type, ticket, ui, signaturePosition) ->
    return if ticket.currentView() is 'customer'

    if type isnt 'email'
      ui.$('.js-vmSender').addClass('hide')
      return

    ui.vmSenderChoices ||= {}
    cached = ui.vmSenderChoices[ticket.id]
    return @render(ui, cached) if cached
    return if ui.vmSenderLoading
    ui.vmSenderLoading = true

    ui.ajax(
      id:   "vm-sender-addresses-#{ticket.id}"
      type: 'GET'
      url:  "#{ui.apiPath}/vm_sender_addresses?ticket_id=#{encodeURIComponent(ticket.id)}"
      success: (data) =>
        ui.vmSenderLoading = false
        ui.vmSenderChoices[ticket.id] = data.addresses or []
        # the agent may have switched to a note meanwhile
        @render(ui, ui.vmSenderChoices[ticket.id]) if ui.type is 'email'
      error: =>
        # no selector is the safe fallback: the reply goes out as it always did
        ui.vmSenderLoading = false
    )

  @render: (ui, addresses) ->
    return if !ui.el?
    return if !addresses or addresses.length < 2

    group = ui.$('.js-vmSender')
    if !group.length
      anchor = ui.$('.js-to').closest('.form-group')
      return if !anchor.length

      group = $('<div class="input form-group js-vmSender"><div class="formGroup-label"><label></label></div><div class="controls"><select class="form-control"></select></div></div>')
      group.find('label').text(App.i18n.translateContent('From'))
      group.find('select').attr('name', @FIELD)
      anchor.before(group)

    select   = group.find('select')
    previous = select.val()
    select.empty()
    for address in addresses
      label = "#{address.name} <#{address.email}>"
      label += " (#{App.i18n.translateContent('default')})" if address.default
      select.append($('<option>').attr('value', address.id).text(label))

    available = _.some(addresses, (address) -> "#{address.id}" is "#{previous}")
    default_  = _.find(addresses, (address) -> address.default)
    select.val(if available then previous else (default_ or addresses[0]).id)

    group.removeClass('hide')

  # Only a deliberate choice of a non-default address leaves the form; the
  # default (or no selector) adds nothing to the request.
  @params: (type, params, ui) ->
    value = params[@FIELD]
    delete params[@FIELD]

    return params if type isnt 'email'
    return params if !value

    default_ = _.find(ui.vmSenderChoices?[ui.ticket_id], (address) -> address.default)
    return params if default_ and "#{default_.id}" is "#{value}"

    params.preferences ||= {}
    params.preferences[@FIELD] = value
    params

App.Config.set('205-VmSenderChoice', VmSenderChoice, 'TicketZoomArticleAction')
