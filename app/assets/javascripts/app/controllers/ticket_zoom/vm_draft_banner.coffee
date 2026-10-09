# "Antwortvorschlag liegt bereit": the ticket's shared draft, one click away,
# directly above the reply box.
#
# The pipeline parks its suggested reply (and, for invoice requests, the PDF) as
# the ticket's shared draft. The stock way to use it is the small "Entwurf
# verfügbar" button in the bottom bar, a modal with a preview, then "Apply": two
# clicks, plus an overwrite question if the reply box has text. For a draft
# that exists on most tickets, that is too much ceremony and too easy to miss.
#
# This banner offers the same thing at the place the agent is looking at.
# "Einfügen" runs exactly what the modal's Apply runs
# (App.TicketSharedDraftModal): import the draft's attachments into the reply
# box, then fill the box through ui::ticket::setArticleType with the draft's
# shared_draft_id, so the draft is consumed when the reply is sent. The draft
# is already in the browser (App.TicketSharedDraftZoom is loaded with the
# ticket), which is why the modal's own GET is not needed for a zoom draft.
# If the reply box already holds text, the same overwrite question appears.
#
# Nothing is ever sent from here. "Einfügen" only fills the reply box; sending
# stays the agent's own click on "Senden". "Verwerfen" deletes the draft (the
# same DELETE the modal uses) and, being final, needs a second click.
#
# Shown only where the bottom-bar button would be: the ticket is editable, the
# group has shared drafts and the agent may change tickets in it. It goes away
# once the draft sits in the reply box (its id is in the form's
# shared_draft_id) and comes back if the box is reset while the draft is still
# there.
class App.VmDraftBanner extends App.Controller
  events:
    'click .js-vmDraftInsert':  'insert'
    'click .js-vmDraftDiscard': 'discard'

  constructor: ->
    super
    @callbackName = "vm_draft_banner_import-#{@controllerId}"
    @busy         = false
    @armed        = false

    @controllerBind(@callbackName, @attachmentsImported)
    # The same signals the bottom-bar button reacts to.
    @controllerBind('ui::ticket::updateSharedDraft', (data) =>
      return if data.taskKey isnt @taskKey
      @newGroupId = data.newGroupId
      @refresh()
    )
    @controllerBind('ui::ticket::setArticleType ui::ticket::shared_draft_saved ui::ticket::taskReset', =>
      # the reply box fills itself after the event, so look one tick later
      @delay(@refresh, 50, 'vm-draft-banner-refresh')
    )
    @refresh()

  draft: =>
    App.TicketSharedDraftZoom.findByAttribute 'ticket_id', @ticket_id

  # Is the draft already sitting in the reply box?
  loadedInReplyBox: (draft) =>
    current = @ui?.articleNew?.el?.find('input[name=shared_draft_id]').val()
    !!current and "#{current}" is "#{draft.id}"

  visible: =>
    draft = @draft()
    return false if !draft
    return false if !@ticket.editable()
    group = App.Group.find(@newGroupId or @ticket.group_id)
    return false if !group?.shared_drafts
    return false if !_.contains(App.User.current().allGroupIds('change'), String(group.id))
    !@loadedInReplyBox(draft)

  refresh: =>
    if !@visible()
      @armed = false
      @el.addClass('hide').empty()
      return
    return if !@el.hasClass('hide') and @el.children().length
    @el
      .removeClass('hide')
      .attr('role', 'status')
      .html(
        "<span class=\"vm-draftbar__text\"><strong>#{@t('Antwortvorschlag liegt bereit')}</strong></span>" +
        "<span class=\"vm-draftbar__actions\">" +
        "<button type=\"button\" class=\"btn btn--action js-vmDraftInsert\">#{@t('Einfügen')}</button>" +
        "<button type=\"button\" class=\"btn btn--text js-vmDraftDiscard\">#{@t('Verwerfen')}</button>" +
        "</span>"
      )

  t: (text) ->
    App.Utils.htmlEscape(App.i18n.translatePlain(text))

  setBusy: (busy) =>
    @busy = busy
    @el.find('button').prop('disabled', busy)

  # --- Einfügen --------------------------------------------------------------

  insert: (e) =>
    e.preventDefault()
    return if @busy or !@draft()

    if App.TaskManager.worker(@taskKey).changed()
      new App.TicketSharedDraftOverwriteModal(
        head:        __('Apply Draft')
        message:     __('There is existing content. Do you want to overwrite it?')
        onSaveDraft: @importAttachments
      )
      return
    @importAttachments()

  importAttachments: =>
    return if !@draft()
    @setBusy(true)
    App.Event.trigger('ui::ticket::import_draft_attachments', {
      shared_draft_id: @draft().id
      ticket_id:       @ticket_id
      callbackName:    @callbackName
    })

  attachmentsImported: (options) =>
    draft = @draft()
    if !options.success or !draft
      @setBusy(false)
      @notify(type: 'error', msg: __('Der Antwortvorschlag konnte nicht eingefügt werden.')) if !options.success
      return

    article = draft.new_article
    App.Event.trigger('ui::ticket::setArticleType', {
      ticket:          { id: @ticket_id }
      type:            { name: article.type }
      article:         article
      nofocus:         true
      shared_draft_id: draft.id
    })
    App.Event.trigger('ui::ticket::load', {
      ticket_id: @ticket_id
      draft:     draft.ticket_attributes
    })
    @setBusy(false)
    @refresh()

  # --- Verwerfen -------------------------------------------------------------

  # Two clicks: the first arms the button, the second deletes. A draft cannot
  # be brought back, and the pipeline's reply is not written a second time.
  discard: (e) =>
    e.preventDefault()
    return if @busy or !@draft()
    button = $(e.currentTarget)

    if !@armed
      @armed = true
      button.text(App.i18n.translatePlain(__('Wirklich verwerfen?')))
      @delay(=>
        @armed = false
        button.text(App.i18n.translatePlain(__('Verwerfen')))
      , 4000, 'vm-draft-banner-disarm')
      return

    @clearDelay('vm-draft-banner-disarm')
    @armed = false
    @setBusy(true)
    @ajax(
      id:   'ticket_shared_draft_delete'
      type: 'DELETE'
      url:  "#{@apiPath}/tickets/#{@ticket_id}/shared_draft"
      success: =>
        @draft()?.remove(clear: true)
        @setBusy(false)
        @ui.draftFetched()
        @refresh()
      error: =>
        @setBusy(false)
        @notify(type: 'error', msg: __('Der Antwortvorschlag konnte nicht verworfen werden.'))
    )
