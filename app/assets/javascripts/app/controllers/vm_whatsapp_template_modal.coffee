# "Send an approved template" -- WhatsApp only allows free-form replies
# within 24h of the customer's last message; after that Meta requires a
# pre-approved message template. Opened from the closed-window alert
# (ticket_zoom/alert.coffee) and from the WhatsApp article action
# (article_action/vm_whatsapp_template.coffee) once the normal reply action
# is hidden.
#
# Loads the ticket channel's approved templates from
# GET /vm_whatsapp/templates, lets the agent fill in the placeholders with a
# live preview, and posts the filled-in template to
# POST /vm_whatsapp/templates/send, which creates the whatsapp-message
# article server-side -- see VmWhatsappTemplatesController. The ticket then
# refreshes through the normal websocket push, same as any other new article.
class App.VmWhatsappTemplateModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Senden')
  head: __('WhatsApp-Vorlage senden')

  constructor: (params) ->
    @ticket    = params.ticket
    @templates = null
    @loadError = null
    super
    @load()

  content: ->
    $(App.view('vm_whatsapp_template_modal')(
      templates: @templates
      loadError: @loadError
    ))

  post: =>
    return if !@templates
    @bindForm()

  load: =>
    @ajax(
      id:   'vm-whatsapp-templates'
      type: 'GET'
      url:  "#{@apiPath}/vm_whatsapp/templates?ticket_id=#{encodeURIComponent(@ticket.id)}"
      success: (data) =>
        if data.error
          @loadError = data.error
        else
          @templates = data.templates or []
        @update()
      error: (xhr) =>
        @loadError = @errorMessage(xhr, __('Die Vorlagen konnten nicht geladen werden.'))
        @update()
    )

  bindForm: =>
    @$('.js-vmTemplateSelect').on('change', @renderFields)
    @renderFields()

  selectedTemplate: =>
    value = @$('.js-vmTemplateSelect').val()
    return null if !value

    [name, language] = value.split('|||')
    _.find(@templates, (t) -> t.name is name and t.language is language)

  renderFields: =>
    template = @selectedTemplate()
    @$('.js-vmTemplateFields').html(App.view('vm_whatsapp_template_fields')(template: template))

    return if !template

    @$('.js-vmTemplateFields input').on('keyup change', @renderPreview)
    @renderPreview()

  renderPreview: =>
    template = @selectedTemplate()
    return if !template

    params = @collectParameters()
    text   = [
      @substitute(template.header, template.placeholders.header, params.header, template.parameter_format)
      @substitute(template.body, template.placeholders.body, params.body, template.parameter_format)
      template.footer
    ].filter((part) -> part).join('\n\n')

    @$('.js-vmTemplatePreview').text(text)

  # `{ header: [{name, value}], body: [{name, value}] }`, in placeholder
  # order -- matches what VmWhatsappTemplatesController#send_template
  # expects for `parameters`.
  collectParameters: =>
    collect = (part) =>
      @$(".js-vmTemplateFields [data-part=\"#{part}\"]").map(->
        name: $(@).attr('data-placeholder-name')
        value: $(@).val()
      ).get()

    header: collect('header')
    body:   collect('body')

  substitute: (text, placeholders, params, parameterFormat) ->
    return '' if !text
    return text if !placeholders or placeholders.length is 0

    result = text
    if parameterFormat is 'NAMED'
      for placeholder in placeholders
        match = _.find(params, (p) -> p.name is placeholder)
        result = result.split("{{#{placeholder}}}").join((match?.value or '…'))
    else
      for placeholder, index in placeholders
        value = params[index]?.value
        result = result.split("{{#{placeholder}}}").join(value or '…')

    result

  onSubmit: (e) =>
    template = @selectedTemplate()
    if !template
      @showAlert(__('Bitte eine Vorlage auswählen.'))
      return

    if !template.supported
      @showAlert(template.unsupported_reason or __('Diese Vorlage wird noch nicht unterstützt.'))
      return

    params = @collectParameters()
    if @hasEmptyValue(params.header) or @hasEmptyValue(params.body)
      @showAlert(__('Bitte alle Platzhalter ausfüllen.'))
      return

    # The submit button sits in the modal footer, outside .js-vmTemplateForm,
    # so the whole form (from the submit event) is disabled against a double send.
    @formDisable(e)

    @ajax(
      id:          'vm-whatsapp-template-send'
      type:        'POST'
      url:         "#{@apiPath}/vm_whatsapp/templates/send"
      processData: true
      data:        JSON.stringify(
        ticket_id:  @ticket.id
        name:       template.name
        language:   template.language
        parameters: params
      )
      success: (data) =>
        @close()
      error: (xhr) =>
        @formEnable(e)
        @showAlert(@errorMessage(xhr, __('Die Vorlage konnte nicht gesendet werden.')))
    )

  hasEmptyValue: (params) ->
    _.some(params, (p) -> !p.value or !p.value.trim())

  errorMessage: (xhr, fallback) ->
    xhr.responseJSON?.error or fallback
