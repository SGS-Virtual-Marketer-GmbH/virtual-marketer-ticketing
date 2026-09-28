class App.TicketZoomArticleNew extends App.Controller
  @include App.SecurityOptions
  @include App.RichtextBubbleMenu

  elements:
    '.js-textarea':                       'textarea'
    '.attachmentPlaceholder':             'attachmentPlaceholder'
    '.attachmentPlaceholder-inputHolder': 'attachmentInputHolder'
    '.attachmentPlaceholder-hint':        'attachmentHint'
    '.article-visibility-text-wrapper':   'visibilityTextWrapper'
    '.article-add':                       'articleNewEdit'
    '.attachments':                       'attachmentsHolder'
    '.attachmentUpload':                  'attachmentUpload'
    '.attachmentUpload-progressBar':      'progressBar'
    '.js-percentage':                     'progressText'
    '.js-cancel':                         'cancelContainer'
    '.textBubble':                        'textBubble'
    '.textBubble-footer':                 'textBubbleFooter'
    '.editControls-item':                 'editControlItem'
    '.js-letterCount':                    'letterCount'
    '.js-signature':                      'signature'
    '.js-voiceRecorder':                  'voiceRecorderEl'
    '.js-voiceRecorderIdle':              'voiceRecorderIdle'
    '.js-voiceRecorderRecording':         'voiceRecorderRecordingEl'
    '.js-voiceRecorderTime':              'voiceRecorderTime'

  events:
    'click .js-toggleVisibility':    'toggleVisibility'
    'click .js-articleTypeItem':     'selectArticleType'
    'click .js-selectedArticleType': 'showSelectableArticleType'
    'click .js-mail-inputs':         'stopPropagation'
    'click .js-writeArea':           'propagateOpenTextarea'
    'click .list-entry-type div':    'changeType'
    'focus .js-textarea':            'openTextarea'
    'input .js-textarea':            'updateLetterCount'
    'blur .js-textarea':             'blurTextarea'
    'click .js-active-toggle':       'toggleButton'
    'click .js-active-toggle-type':  'toggleTypeButton'
    'click .js-voiceRecorderStart':  'startVoiceRecording'
    'click .js-voiceRecorderStop':   'stopVoiceRecording'
    'click .js-voiceRecorderCancel': 'cancelVoiceRecording'

  constructor: ->
    super

    @internalSelector = false
    @setPossibleArticleTypes()
    @type = @normalizeArticleType(@defaults['type'] || 'note')

    if @ticket.currentView() is 'agent'
      @internalSelector = true

    @textareaHeight =
      open:   148
      closed: 20

    @dragEventCounter = 0
    @attachments      = @defaults.attachments || []

    @render()

    # set article type and expand text area
    @controllerBind('ui::ticket::setArticleType', (data) =>
      return if data.ticket.id.toString() isnt @ticket_id.toString()

      @setArticleTypePre(data.type.name, data.signaturePosition)

      @openTextarea(null, true, !data.nofocus)
      for key, value of data.article
        switch key
          when 'body'
            @$("[data-name=\"#{key}\"]").html(value)
          when 'internal'
            @setArticleInternal(value)
          else
            @$("[name=\"#{key}\"]").val(value).trigger('change')

      @$('[name=shared_draft_id]').val(data.shared_draft_id)

      @setArticleTypePost(data.type.name, data.signaturePosition)

      # set focus into field
      if data.focus
        @$("[name=\"#{data.focus}\"], [data-name=\"#{data.focus}\"]").trigger('focus').parent().find('.token-input').trigger('focus')
        return

      # set focus at end of field
      if data.position is 'end'
        @placeCaretAtEnd(@textarea.get(0))
        return

      # fixes email validation issue right after new ticket creation
      @tokanice(data.type.name)
    )

    @controllerBind('ui::ticket::import_draft_attachments', @importDraftAttachments)
    @controllerBind('ui::ticket::shared_draft_saved',       @sharedDraftSaved)

    # add article attachment
    @controllerBind('ui::ticket::addArticleAttachment', (data) =>
      return if data.ticket?.id?.toString() isnt @ticket_id.toString() && data.form_id isnt @form_id
      return if _.isEmpty(data.attachments)
      for file in data.attachments
        @renderAttachment(file)
    )

    # reset new article screen
    @controllerBind('ui::ticket::taskReset', (data) =>
      @releaseGlobalClickEvents()
      return if data.ticket_id.toString() isnt @ticket_id.toString()
      @type        = 'note'
      @defaults    = {}
      @attachments = []
      @render()
    )

    # rerender, e. g. on language change
    @controllerBind('ui:rerender', =>
      @adjustedTextarea = false
      @defaults         = @ui.taskGet('article')
      @attachments      = @defaults.attachments || []
      @render()
    )

    # update security options
    @controllerBind('ui::ticket::updateSecurityOptions', (data) =>
      return if data.taskKey isnt @taskKey

      @updateSecurityType()
      @updateSecurityOptions()
    )

    # update signature when group changes
    @controllerBind('ui::ticket::updateSignature', (data) =>
      return if data.taskKey isnt @taskKey

      @updateSignatureByGroup(data.newGroupId)
    )

    # Listen to security setting changes.
    @controllerBind('config_update', (data) =>
      return if not /^(pgp|smime)_integration$/.test(data.name)

      @updateSecurityType()
      @updateSecurityOptions()
    )

  show: ->
    @adjustTextarea()

  adjustTextarea: ->
    return if @adjustedTextarea
    @adjustedTextarea = true

    @tokanice(@type)

    if @defaults.body or @attachments.length > 0 or @isIE10()
      @openTextarea(null, true)

  tokanice: (type = 'email') ->
    App.Utils.tokanice('.content.active .js-to, .js-cc, js-bcc', type)

  setPossibleArticleTypes: =>
    @articleTypes = []
    for config in @actions()
      if config && config.articleTypes
        @articleTypes = config.articleTypes(@articleTypes, @ticket, @)

  normalizeArticleType: (type) =>
    return if not type

    articleTypeExists = _.some(@articleTypes, (articleType) -> articleType?.name is type)
    return type if articleTypeExists

    if @ticket?.currentView() is 'customer'
      fallback = _.find(@articleTypes, (articleType) -> articleType?.name?)
      return fallback?.name || 'note'

    type

  placeCaretAtEnd: (el) ->
    el.focus()
    if typeof window.getSelection isnt 'undefined' && typeof document.createRange isnt 'undefined'
      range = document.createRange()
      range.selectNodeContents(el)
      range.collapse(false)
      sel = window.getSelection()
      sel.removeAllRanges()
      sel.addRange(range)
      return
    if typeof document.body.createTextRange isnt 'undefined'
      textRange = document.body.createTextRange()
      textRange.moveToElementText(el)
      textRange.collapse(false)
      textRange.select()

  isIE10: ->
    detected = App.Browser.detection()
    return false if !detected.browser
    return false if detected.browser.name != 'Explorer'
    return detected.browser.major == 10

  release: =>
    if @subscribeIdTextModule
      App.Ticket.unsubscribe(@subscribeIdTextModule)

    @releaseGlobalClickEvents()
    @voiceRecorderStopTimer()
    @voiceRecorderCleanupStream()

  releaseGlobalClickEvents: ->
    $(window).off 'click.ticket-zoom-select-type'
    $(window).off 'click.ticket-zoom-textarea'

  render: ->
    @releaseGlobalClickEvents()
    ticket = App.Ticket.fullLocal(@ticket_id)

    @html App.view('ticket_zoom/article_new')(
      ticket:           ticket
      articleTypes:     @articleTypes
      article:          @defaults
      form_id:          @form_id
      isCustomer:       ticket.currentView() is 'customer'
      internalSelector: @internalSelector
    )
    @setArticleTypePre(@type)
    @setArticleTypePost(@type)

    if @defaults.internal != undefined
      @setArticleInternal(@defaults.internal)

    new App.WidgetAvatar(
      el:        @$('.js-avatar')
      object_id: App.Session.get('id')
      size:      40
      position:  'right'
    )

    @tokanice(@type)

    @$('[data-name="body"]').ce({
      mode:      'richtext'
      multiline: true
      maxlength: 150000
    })

    new App.Html5Upload(
      uploadUrl:              "#{App.Config.get('api_path')}/upload_caches/#{@form_id}"
      dropContainer:          @$('.article-add')
      cancelContainer:        @cancelContainer
      inputField:             @$('.article-attachment input')
      canUploadFiles:         @canUploadFiles

      onFileStartCallback: =>
        @richTextUploadStartCallback?()

      onFileCompletedCallback: (response) =>
        @attachments.push response.data
        @renderAttachment(response.data)
        @$('.article-attachment input').val('')

        @richTextUploadRenderCallback?(@attachments)

      onFileAbortedCallback: =>
        @richTextUploadRenderCallback?(@attachments)

      onFileErrorCallback: =>
        @richTextUploadRenderCallback?(@attachments)

      attachmentPlaceholder: @attachmentPlaceholder
      attachmentUpload:      @attachmentUpload
      progressBar:           @progressBar
      progressText:          @progressText
    ).render()

    @bindAttachmentDelete()

    # show text module UI
    if ticket.currentView() is 'agent'
      @textModule?.releaseController()
      @textModule = new App.WidgetTextModule(
        el: @$('.js-textarea').parent()
        data:
          ticket: ticket
          user:   App.Session.get()
          config: App.Config.all()
        taskKey: @taskKey
      )
      if !@subscribeIdTextModule
        callback = (ticket) =>
          @textModule.reload(
            ticket: ticket
            user: App.Session.get()
            config: App.Config.all()
          )
        @subscribeIdTextModule = ticket.subscribe(callback)

      @textTools?.releaseController()
      @textTools = new App.WidgetTextTools(
        el: @$('.js-textarea').parent()
        data:
          ticket: ticket
          user:   App.Session.get()
        taskKey: @taskKey
      )
      if !@subscribeIdTextTools
        @subscribeIdTextTools = ticket.subscribe((ticket) =>
          @textTools.reload(
            ticket: ticket
            user:   App.Session.get()
          )
        )

    if _.isArray(@attachments)
      for attachment in @attachments
        @renderAttachment(attachment)

    @richtextBubbleMenuInit(@textarea.parent(), false)

  params: =>
    params = @formParam( @$('.article-add') )

    needsNoCaption  = @checkBodyEnsureNoCaption()
    allowsNoCaption = @checkBodyAllowNoCaption()

    if params.body || needsNoCaption || allowsNoCaption
      params.from         = @Session.get().displayName()
      params.ticket_id    = @ticket_id
      params.form_id      = @form_id
      params.content_type = 'text/html'

      ticket = App.Ticket.find(@ticket_id)

      if ticket.currentView() is 'agent'
        sender           = App.TicketArticleSender.findByAttribute('name', 'Agent')
        type             = App.TicketArticleType.findByAttribute('name', params['type'])
        params.sender_id = sender.id
        params.type_id   = type.id
      else
        sender           = App.TicketArticleSender.findByAttribute('name', 'Customer')
        type             = App.TicketArticleType.findByAttribute('name', 'web')
        params.type_id   = type.id
        params.sender_id = sender.id

    if params.internal
      params.internal = true
    else
      params.internal = false

    # backend based validation
    for config in @actions()
      if config && config.params
        params = config.params(params.type, params, @)

    # add initials?
    for articleType in @articleTypes
      if articleType.name is @type
        if _.contains(articleType.features, 'body:initials')
          if params.content_type is 'text/html'
            params.body = "#{params.body}</br>#{@signature.text()}"
          else
            params.body = "#{params.body}\n#{@signature.text()}"
          break

    # add security params
    if @securityOptionsShown()
      params.preferences ||= {}
      params.preferences.security = @paramsSecurity()

    if needsNoCaption
      params.body = ''
    else if allowsNoCaption
      params.body ||= ''

    params

  validate: =>
    params = @params()

    return false if !@validateBodyLimit(params.body)
    return false if !@validateAttachmentsLimit()
    return false if !@validateAttachmentsSize()

    # check if attachment exists but no body
    if !@validateBodyPresence(params.body)
      new App.ControllerModal(
        head: __('Text missing')
        buttonCancel: __('Cancel')
        buttonCancelClass: 'btn--danger'
        buttonSubmit: false
        message: __('Please enter a text.')
        shown: true
        small: true
        container: @el.closest('.content')
      )
      return false

    attachmentCount = @$('.article-add .textBubble .attachments .attachment').length
    # check attachment
    if params.body && attachmentCount < 1
      matchingWord = App.Utils.checkAttachmentReference(params.body)
      if matchingWord
        if !confirm(App.i18n.translateContent('You used %s in the text but no attachment could be found. Do you want to continue?', matchingWord))
          return false

    # backend based validation
    for config in @actions()
      if config && config.validation
        return false if !config.validation(params.type, params, @)

    true

  validateBodyPresence: (body) =>
    body || @checkBodyAllowEmpty() || @attachments.length == 0

  validateBodyLimit: (body) =>
    return true if !@maxTextLength

    App.Utils.textLengthWithUrl(body) <= @maxTextLength

  validateAttachmentsLimit: =>
    return true if !@attachmentsLimit

    @attachments.length <= @attachmentsLimit

  validateAttachmentsSize: =>
    return true if !@attachmentsSize

    !@errorExistingAttachmentsSize()

  changeType: (e) ->
    $(e.target).addClass('active').siblings('.active').removeClass('active')

  toggleVisibility: (e, internal) ->
    e.stopPropagation()
    if @articleNewEdit.hasClass('is-public')
      @setArticleInternal(true)
    else
      if App.Config.get('ui_ticket_zoom_article_visibility_confirmation_dialog')
        new App.ControllerArticlePublicConfirm(
          callback: =>
            @setArticleInternal(false)
          container: $(e.target).closest('.content')
        )
      else
        @setArticleInternal(false)

    @textarea.trigger('change.local')
    App.Event.trigger('ui::ticket::articleNew::change', { ticket_id: @ticket.id })

  showSelectableArticleType: (event) =>
    event.stopPropagation()
    @el.find('.js-articleTypes').removeClass('is-hidden')
    $(window).on 'click.ticket-zoom-select-type', @hideSelectableArticleType

  selectArticleType: (event) =>
    event.stopPropagation()
    articleTypeToSet = $(event.target).closest('.pop-selectable').data('value')
    @setArticleTypePre(articleTypeToSet)
    @hideSelectableArticleType()
    @setArticleTypePost(articleTypeToSet)
    App.Event.trigger('ui::ticket::articleNew::change', { ticket_id: @ticket.id })

    $(window).off('click.ticket-zoom-select-type')
    @tokanice(articleTypeToSet)

  hideSelectableArticleType: =>
    @el.find('.js-articleTypes').addClass('is-hidden')

  setArticleInternal: (internal) =>
    @articleNewEdit
      .toggleClass('is-public', !internal)
      .toggleClass('is-internal', internal)

    visibilityTextType = "#{@type}-#{if internal then 'internal' else 'public'}"

    @visibilityTextWrapper
      .find('.article-visibility-text')
      .addClass('is-hidden')
      .attr('aria-hidden', true)
      .filter("[data-type='#{visibilityTextType}']")
      .removeClass('is-hidden')
      .removeAttr('aria-hidden')

    value = if internal then 'true' else ''
    @$('[name=internal]').val(value)

  setArticleTypePre: (type, signaturePosition = 'bottom') =>
    type = @normalizeArticleType(type)
    wasScrolledToBottom = @isScrolledToBottom()

    # a running recording has no meaning outside the whatsapp message type
    # it was started in - abandon it rather than let it record on unseen
    @cancelVoiceRecording() if @voiceRecorderActive && type isnt 'whatsapp message'

    # reset old params
    if type isnt @type
      for key in ['to', 'cc', 'bcc', 'subject', 'in_reply_to']
        @$("[name=#{key}]").val('').trigger('change')

    @type = type
    @$('[name=type]').val(type).trigger('change')
    @articleNewEdit.attr('data-type', type)
    @$('.js-selectableTypes').addClass('hide').filter("[data-type='#{type}']").removeClass('hide')

    @setPossibleArticleTypes()
    type = @normalizeArticleType(type)

    # get config
    config = {}
    for articleTypeConfig in @articleTypes
      if articleTypeConfig.name is type
        config = articleTypeConfig

    if config
      if config.internal
        @setArticleInternal(true)
      else
        @setArticleInternal(false)

    # show/hide attributes/features
    @maxTextLength       = undefined
    @warningTextLength   = undefined
    @attachmentsLimit    = undefined
    @attachmentsSize     = undefined
    @bodyEnsureNoCaption = undefined
    @bodyAllowNoCaption  = undefined

    for articleType in @articleTypes
      if articleType.name is type
        @$('.form-group').addClass('hide')
        for name in articleType.attributes
          @$("[name=#{name}]").closest('.form-group').removeClass('hide')
        @$('.article-attachment, .attachments, .js-textSizeLimit').addClass('hide')
        @voiceRecorderEl?.addClass('hide')
        for name in articleType.features
          switch name
            when 'attachment'
              @$('.article-attachment, .attachments').removeClass('hide')
            when 'voice:record'
              @voiceRecorderEl?.removeClass('hide')
            when 'body:initials'
              @updateInitials()
            when 'body:limit'
              @maxTextLength = articleType.maxTextLength
              @warningTextLength = articleType.warningTextLength
              @delay(@updateLetterCount, 600)
              @$('.js-textSizeLimit').removeClass('hide')
            when 'security'
              if @securityEnabled()
                @securityOptionsShow()

                # add observer to change options
                @$('.js-to, .js-cc').on('change', =>
                  @updateSecurityOptions()
                )

                @updateSecurityType()
                @updateSecurityOptions()
            when 'attachments:limit'
              @attachmentsLimit = articleType.attachmentsLimit
            when 'attachments:size'
              @attachmentsSize = articleType.attachmentsSize
            when 'body:ensureNoCaption'
              @bodyEnsureNoCaption = articleType.bodyEnsureNoCaption
            when 'body:allowNoCaption'
              @bodyAllowNoCaption = articleType.bodyAllowNoCaption

    # convert remote src images to data uri
    App.Utils.htmlImage2DataUrlAsyncInline(@$('[data-name=body]'))

    @scrollToBottom() if wasScrolledToBottom

  updateSecurityOptions: (resetSecurityOptions = false) =>
    @securityOptionsReset() if resetSecurityOptions
    @updateSecurityOptionsRemote(@taskKey, @ui.ticketParams(), @params())

  updateSecurityType: (type = @type) =>
    return if type isnt 'email'

    @updateSecurityTypeToolbar()

  setArticleTypePost: (type, signaturePosition = undefined) =>
    for localConfig in @actions()
      if localConfig && localConfig.setArticleTypePost
        localConfig.setArticleTypePost(@type, @ticket, @, signaturePosition)

    @evaluateAttachmentsList()

  updateSignatureByGroup: (newGroupId) =>
    for localConfig in @actions()
      if localConfig && localConfig.updateSignatureByGroup
        localConfig.updateSignatureByGroup(@type, @ticket, @, newGroupId)

  isScrolledToBottom: ->
    return @el.scrollParent().scrollTop() + @el.scrollParent().height() is @el.scrollParent().prop('scrollHeight')

  scrollToBottom: ->
    @el.scrollParent().scrollTop @el.scrollParent().prop('scrollHeight')

  propagateOpenTextarea: (event) ->
    event.stopPropagation()
    @textarea.trigger('focus')

  updateLetterCount: =>
    return if !@maxTextLength
    return if !@warningTextLength
    params = @params()
    textLength = App.Utils.textLengthWithUrl(params.body)
    textLength = @maxTextLength - textLength
    className = switch
      when textLength < 0 then 'label-danger'
      when textLength < @warningTextLength then 'label-warning'
      else ''

    @letterCount
      .text textLength
      .removeClass 'label-danger label-warning'
      .addClass className

  blurTextarea: =>
    App.Event.trigger('ui::ticket::articleNew::change', { ticket_id: @ticket.id })

  updateInitials: (value) =>
    if value is undefined
      value = "/#{App.User.find(@Session.get('id')).initials()}"
    @signature.text(value)

  openTextarea: (event, withoutAnimation, focus) =>
    if event
      event.stopPropagation()
    if @articleNewEdit.hasClass('is-open')
      return

    $(window).off('click.ticket-zoom-textarea')

    duration = 300

    if withoutAnimation
      duration = 0

    @articleNewEdit.addClass('is-open')

    @textarea.velocity
      properties:
        minHeight: "#{ @textareaHeight.open - 38 }px"
      options:
        duration: duration
        easing: 'easeOutQuad'
        complete: =>
          $(window).on('click.ticket-zoom-textarea', @closeTextarea)
          @textarea.trigger('focus') if focus

    @textBubble.velocity
      properties:
        paddingBottom: 28
      options:
        duration: duration
        easing: 'easeOutQuad'

    # scroll to bottom
    @textarea.velocity 'scroll',
      container: @textarea.scrollParent()
      offset: 99999
      duration: 300
      easing: 'easeOutQuad'
      queue: false

    @editControlItem
      .removeClass('is-hidden')
      .velocity
        properties:
          opacity: [ 1, 0 ]
          translateX: [ 0, 20 ]
          translateZ: 0
        options:
          duration: 300
          stagger: 50
          drag: true

    @visibilityTextWrapper.velocity
      properties:
        opacity: 1
        height: '100%'
      options:
        duration: 300
        easing: 'easeOutQuad'

    # move attachment text to the left bottom (bottom happens automatically)
    @attachmentPlaceholder.velocity
      properties:
        translateX: -@attachmentInputHolder.position().left + 'px'
      options:
        duration: duration
        easing: 'easeOutQuad'

    @attachmentHint.velocity
      properties:
        opacity: 0
      options:
        duration: duration

  closeTextarea: =>
    if !@textarea.text().trim() && !@attachments.length && not @isIE10()
      $(window).off 'click.ticket-zoom-textarea'

      @textarea.velocity
        properties:
          minHeight: "#{ @textareaHeight.closed }px"
        options:
          duration: 300
          easing: 'easeOutQuad'
          complete: => @articleNewEdit.removeClass('is-open')

      @textBubble.velocity
        properties:
          paddingBottom: 10
        options:
          duration: 300
          easing: 'easeOutQuad'

      @textBubbleFooter.velocity
        properties:
          opacity: 0
        options:
          duration: 300
          easing: 'easeOutQuad'
          complete: => @textBubbleFooter.css(opacity: 1)

      @attachmentPlaceholder.velocity
        properties:
          translateX: 0
        options:
          duration: 300
          easing: 'easeOutQuad'

      @attachmentHint.velocity
        properties:
          opacity: 1
        options:
          duration: 300

      @editControlItem
        .velocity
          properties:
            opacity: [ 0, 1 ]
            translateX: [ 20, 0 ]
            translateZ: 0
          options:
            duration: 100
            stagger: 50
            drag: true
            complete: (elements) -> $(elements).addClass('is-hidden')

      @visibilityTextWrapper.velocity
        properties:
          opacity: 0
          height: 0
        options:
          duration: 300
          easing: 'easeOutQuad'

  onDragenter: (event) =>
    # on the first event,
    # open textarea (it will only open if its closed)
    @openTextarea() if @dragEventCounter is 0

    @dragEventCounter++
    @articleNewEdit.parent().addClass('is-dropTarget')

  onDragleave: (event) =>
    @dragEventCounter--

    @articleNewEdit.parent().removeClass('is-dropTarget') if @dragEventCounter is 0

  renderAttachment: (file) =>
    @attachmentsHolder.append(App.view('generic/attachment_item')(file))
    @evaluateAttachmentsList()

  bindAttachmentDelete: =>
    @attachmentsHolder.on('click', '.js-delete', (e) =>
      id = $(e.currentTarget).data('id')
      @attachments = _.filter(
        @attachments,
        (item) ->
          return if item.id.toString() is id.toString()
          item
      )

      # delete attachment from storage
      App.Ajax.request(
        type:        'DELETE'
        url:         "#{App.Config.get('api_path')}/upload_caches/#{@form_id}/items/#{id}"
        processData: false
      )

      # remove attachment from dom
      element = $(e.currentTarget).closest('.attachments')
      $(e.currentTarget).closest('.attachment').remove()
      if element.find('.attachment').length == 0
        element.empty()

      @richTextUploadDeleteCallback?(@attachments)
      @evaluateAttachmentsList()
    )

  importDraftAttachments: (options) =>
    return if @ticket.id != options.ticket_id

    @ajax
      id: 'import_attachments'
      type: 'POST'
      url: "#{@apiPath}/tickets/#{@ticket.id}/shared_draft/import_attachments"
      data: JSON.stringify({ form_id: @form_id })
      processData: true
      success: (data, status, xhr) =>
        App.Event.trigger('ui::ticket::addArticleAttachment', {
          ticket:      @ticket
          attachments: data.attachments
          form_id:     @form_id
        })

        App.Event.trigger(options.callbackName, { success: true })
      error: ->
        App.Event.trigger(options.callbackName, { success: false })

  sharedDraftSaved: (options) =>
    return if @ticket.id != options.ticket_id

    @el
      .find('input[name=shared_draft_id]')
      .val(options.shared_draft_id)

  actions: ->
    actionConfig = App.Config.get('TicketZoomArticleAction')
    keys = _.keys(actionConfig).sort()
    actions = []
    for key in keys
      localConfig = actionConfig[key]
      if localConfig
        actions.push localConfig
    actions

  toggleButton: (event) ->
    @$(event.currentTarget).toggleClass('btn--active')

  toggleTypeButton: (event) ->
    target = @$(event.currentTarget)

    return if target.hasClass('btn--active')

    target.siblings().removeClass('btn--active')

    @toggleButton(event)
    @updateSecurityOptions(true)

  canUploadFiles: (files) =>
    if @errorAttachmentsLimit(files)
      new App.ErrorModal(
        head: __('Cannot upload file')
        contentInline: @errorAttachmentsLimitMessage()
        container: @el.closest('.content')
      )

      return false

    if file = @errorNewAttachmentsSize(files)
      new App.ErrorModal(
        head: __('Cannot upload file')
        contentInline: @errorAttachmentsSizeMessage(file)
        container: @el.closest('.content')
      )

      return false

    true

  errorAttachmentsLimit: (newFiles = []) =>
    return false if !@attachmentsLimit

    futureFilesCount = @attachments.length + newFiles.length

    @attachmentsLimit < futureFilesCount

  errorAttachmentsLimitMessage: =>
    App.i18n.translateContent(__('Only %s attachment allowed.'), @attachmentsLimit)

  errorNewAttachmentsSize: (files) =>
    return false if !@attachmentsSize

    Array.from(files).find (file) =>
      config = @attachmentSizeByFile(file)

      return true if !config

      config && file.size > config.size

  errorExistingAttachmentsSize: =>
    return false if !@attachmentsSize

    @attachments.find (file) =>
      config   = @attachmentSizeByFile(file)

      return true if !config

      fileSize = parseInt(file.size)

      config && fileSize > config.size

  errorAttachmentsSizeMessage: (file) =>
    sizeConfig = @attachmentSizeByFile(file)

    if !sizeConfig
      return App.i18n.translateContent(
        __('The file type %s is not allowed.'),
        @attachmentContentType(file)
      )


    App.i18n.translateContent(
      __('File is too big. %s has to be %s or smaller.'),
      App.i18n.translateContent(sizeConfig?.label),
      App.Utils.humanFileSize(sizeConfig?.size)
    )

  attachmentSizeByFile: (file) =>
    contentType         = @attachmentContentType(file)

    @attachmentsSize.find (elem) -> elem.content_types.includes(contentType)

  attachmentContentType: (file) ->
    file.type || file.contentType || file.preferences?['Content-Type'] || file.preferences?['Mime-Type']

  checkBodyEnsureNoCaption: =>
    return false if !@bodyEnsureNoCaption

    @bodyEnsureNoCaption(@attachments.map (file) => @attachmentContentType(file))

  checkBodyAllowNoCaption: =>
    return false if !@bodyAllowNoCaption

    @bodyAllowNoCaption(@attachments)

  checkBodyAllowEmpty: =>
    @checkBodyEnsureNoCaption() || @checkBodyAllowNoCaption()

  evaluateAttachmentsList: =>
    @toggleBodyEnsureNoCaption @checkBodyEnsureNoCaption()

    @attachmentsHolder.find('.alert--danger').remove()

    @attachmentInputHolder
      .find('input')
      .attr('disabled', @attachmentsLimit == @attachments.length)
      .attr('multiple', @attachmentsLimit != 1)

    if @errorAttachmentsLimit()
      $('<div class="alert alert--danger js-alert-attachments-limit"></div>')
        .text(@errorAttachmentsLimitMessage())
        .prependTo(@attachmentsHolder)

      return

    tooBigFile = @errorExistingAttachmentsSize()

    return if !tooBigFile

    $('<div class="alert alert--danger js-alert-attachments-size"></div>')
      .text(@errorAttachmentsSizeMessage(tooBigFile))
      .prependTo(@attachmentsHolder)

  toggleBodyEnsureNoCaption: (noCaption) =>
    @textarea
      .attr('contenteditable', !noCaption)
      .toggleClass('text-muted', noCaption)

    @attachmentsHolder.find('.alert--warning').remove()

    return if !noCaption

    $('<div class="alert alert--warning js-warning-body-presence"></div>')
      .text(noCaption)
      .prependTo(@attachmentsHolder)

  # -------------------------------------------------------------------------
  # WhatsApp voice messages: record in the browser, remux to Ogg Opus (the
  # only Opus-flavoured format WhatsApp's Cloud API accepts - its own
  # MediaRecorder 'audio/mp4' option actually contains an Opus payload, not
  # AAC, and would silently be rejected/misread by WhatsApp) and hand the
  # result to the exact same attachment upload path a manually-picked file
  # would go through, so it shows up in the attachment list and respects
  # attachmentsLimit/size like any other attachment.
  #
  # Codec choice, in order:
  #   1. audio/ogg;codecs=opus  - used as recorded (Firefox)
  #   2. audio/webm;codecs=opus - remuxed via window.VmOggOpus (Chrome/Chromium)
  #   3. audio/mp4 (AAC)        - used as recorded, but ONLY on a non-Chromium
  #                                browser (Safari), since Chromium's mp4
  #                                option is Opus-in-mp4, not AAC-in-mp4.
  voiceRecorderMaxSeconds: 300

  voiceRecorderPickFormat: =>
    return null if !window.MediaRecorder

    if MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
      return { mimeType: 'audio/ogg;codecs=opus', remux: false, extension: 'ogg', outputType: 'audio/ogg' }

    if MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      return { mimeType: 'audio/webm;codecs=opus', remux: true, extension: 'ogg', outputType: 'audio/ogg' }

    if !@voiceRecorderIsChromium()
      if MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a.40.2')
        return { mimeType: 'audio/mp4;codecs=mp4a.40.2', remux: false, extension: 'm4a', outputType: 'audio/mp4' }
      if MediaRecorder.isTypeSupported('audio/mp4')
        return { mimeType: 'audio/mp4', remux: false, extension: 'm4a', outputType: 'audio/mp4' }

    null

  # Chromium's MediaRecorder reports 'audio/mp4' as supported, but the
  # payload inside is Opus, not AAC - unusable for WhatsApp. UAParser's
  # rendering engine (Blink = every Chromium-based browser) is a more
  # reliable signal for this than the browser name, since Edge/Opera/etc.
  # all share the same trap.
  voiceRecorderIsChromium: =>
    return @voiceRecorderIsChromiumCache if @voiceRecorderIsChromiumCache isnt undefined

    engineName = undefined
    try
      engineName = new UAParser().getEngine()?.name
    catch error
      engineName = undefined
    @voiceRecorderIsChromiumCache = engineName is 'Blink'
    @voiceRecorderIsChromiumCache

  startVoiceRecording: (event) =>
    event?.stopPropagation()

    return if @voiceRecorderActive

    if !navigator.mediaDevices?.getUserMedia || !window.MediaRecorder
      @voiceRecorderError(__('Ihr Browser unterstützt keine Sprachnachrichten.'))
      return

    format = @voiceRecorderPickFormat()
    if !format
      @voiceRecorderError(__('Ihr Browser unterstützt keine Sprachnachrichten.'))
      return

    navigator.mediaDevices.getUserMedia(audio: true)
      .then( (stream) => @voiceRecorderBegin(stream, format) )
      .catch( (error) =>
        App.Log.error('TicketZoomArticleNew', 'voice message getUserMedia failed', error)
        @voiceRecorderError(__('Der Zugriff auf das Mikrofon wurde verweigert. Bitte erlauben Sie den Mikrofonzugriff in Ihren Browsereinstellungen.'))
      )

  voiceRecorderBegin: (stream, format) =>
    @voiceRecorderActive  = true
    @voiceRecorderStream  = stream
    @voiceRecorderChunks  = []
    @voiceRecorderFormat  = format
    @voiceRecorderStarted = Date.now()
    @voiceRecorderFinalize = false

    recorder = undefined
    try
      recorder = new MediaRecorder(stream, mimeType: format.mimeType)
    catch error
      App.Log.error('TicketZoomArticleNew', 'voice message MediaRecorder construction failed', error)
      @voiceRecorderError(__('Die Aufnahme konnte nicht gestartet werden.'))
      @voiceRecorderCleanupStream()
      @voiceRecorderActive = false
      return

    @voiceRecorderRecorder = recorder

    recorder.ondataavailable = (event) =>
      @voiceRecorderChunks.push(event.data) if event.data?.size > 0

    recorder.onstop = @voiceRecorderHandleStop

    recorder.onerror = (event) =>
      App.Log.error('TicketZoomArticleNew', 'voice message MediaRecorder error', event.error)
      @voiceRecorderFinalize = false

    recorder.start()

    @voiceRecorderIdle.addClass('hide')
    @voiceRecorderRecordingEl.removeClass('hide')
    @voiceRecorderUpdateTime()
    @voiceRecorderTimerId = setInterval(@voiceRecorderUpdateTime, 1000)

  voiceRecorderUpdateTime: =>
    return if !@voiceRecorderActive

    elapsed = Math.floor((Date.now() - @voiceRecorderStarted) / 1000)

    if elapsed >= @voiceRecorderMaxSeconds
      @stopVoiceRecording()
      return

    minutes = Math.floor(elapsed / 60)
    seconds = elapsed % 60
    secondsPadded = if seconds < 10 then "0#{seconds}" else "#{seconds}"
    @voiceRecorderTime.text("#{minutes}:#{secondsPadded}")

  stopVoiceRecording: (event) =>
    event?.stopPropagation()
    return if !@voiceRecorderActive

    @voiceRecorderFinalize = true
    @voiceRecorderRecorder?.stop()

  cancelVoiceRecording: (event) =>
    event?.stopPropagation()
    return if !@voiceRecorderActive

    @voiceRecorderFinalize = false
    @voiceRecorderRecorder?.stop()

  voiceRecorderHandleStop: =>
    @voiceRecorderStopTimer()

    finalize = @voiceRecorderFinalize
    format   = @voiceRecorderFormat
    chunks   = @voiceRecorderChunks

    @voiceRecorderCleanupStream()
    @voiceRecorderReset()

    return if !finalize
    return if _.isEmpty(chunks)

    blob = new Blob(chunks, type: format.mimeType.split(';')[0])

    if !format.remux
      @voiceRecorderUpload(blob, format)
      return

    reader = new FileReader()
    reader.onload = =>
      oggBytes = undefined
      try
        oggBytes = window.VmOggOpus.fromWebm(reader.result)
      catch error
        App.Log.error('TicketZoomArticleNew', 'VmOggOpus remux failed', error)
        @voiceRecorderError(__('Die Aufnahme konnte nicht verarbeitet werden.'))
        return
      @voiceRecorderUpload(new Blob([oggBytes], type: format.outputType), format)
    reader.onerror = =>
      App.Log.error('TicketZoomArticleNew', 'voice message FileReader failed', reader.error)
      @voiceRecorderError(__('Die Aufnahme konnte nicht verarbeitet werden.'))
    reader.readAsArrayBuffer(blob)

  voiceRecorderStopTimer: =>
    if @voiceRecorderTimerId
      clearInterval(@voiceRecorderTimerId)
      @voiceRecorderTimerId = null

  voiceRecorderCleanupStream: =>
    if @voiceRecorderStream
      track.stop() for track in @voiceRecorderStream.getTracks()
    @voiceRecorderStream = null

  voiceRecorderReset: =>
    @voiceRecorderActive   = false
    @voiceRecorderRecorder = null
    @voiceRecorderChunks   = []

    @voiceRecorderRecordingEl?.addClass('hide')
    @voiceRecorderIdle?.removeClass('hide')
    @voiceRecorderTime?.text('0:00')

  voiceRecorderUpload: (blob, format) =>
    filename = "Sprachnachricht-#{@voiceRecorderFilenameTimestamp()}.#{format.extension}"
    file = new File([blob], filename, type: format.outputType)

    dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)

    input = @el.find('.article-attachment input[type=file]').get(0)
    return if !input

    # go through the exact same path a manually-picked/dropped file would:
    # html5Upload's rebound 'change' listener on this input reads
    # this.files and calls processFiles(), including the existing
    # attachmentsLimit/size validation (canUploadFiles).
    input.files = dataTransfer.files
    input.dispatchEvent(new Event('change', bubbles: true))

  voiceRecorderFilenameTimestamp: ->
    now = new Date()
    pad = (number) -> if number < 10 then "0#{number}" else "#{number}"
    "#{now.getFullYear()}-#{pad(now.getMonth() + 1)}-#{pad(now.getDate())}-#{pad(now.getHours())}#{pad(now.getMinutes())}"

  voiceRecorderError: (message) =>
    @voiceRecorderStopTimer()
    @voiceRecorderCleanupStream()
    @voiceRecorderReset()

    new App.ErrorModal(
      head:          __('Sprachnachricht')
      contentInline: message
      container:     @el.closest('.content')
    )
