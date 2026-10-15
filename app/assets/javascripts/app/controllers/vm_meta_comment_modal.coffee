# One modal for both comment moderation actions (see
# ticket_zoom/article_action/vm_meta_comment.coffee):
#   mode 'private' -> text box, sends a private reply to the comment
#   mode 'hide'    -> confirmation, hides the comment on the platform
# The result is written to the ticket as an internal note by the server, so
# the ticket refreshes through the normal websocket push.
class App.VmMetaCommentModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true

  constructor: (params) ->
    @ticket = params.ticket
    @mode   = params.mode
    @head         = if @mode is 'private' then __('Privat antworten') else __('Kommentar verbergen')
    @buttonSubmit = if @mode is 'private' then __('Privat senden') else __('Verbergen')
    super

  content: ->
    $(App.view('vm_meta_comment_modal')(mode: @mode))

  onSubmit: (e) =>
    if @mode is 'private'
      body = $.trim(@$('.js-vmCommentText').val())
      if !body
        @showAlert(__('Bitte einen Text eingeben.'))
        return
      url  = "#{@apiPath}/vm_meta_comments/#{@ticket.id}/private_reply"
      data = { body: body }
    else
      url  = "#{@apiPath}/vm_meta_comments/#{@ticket.id}/hide"
      data = { hidden: true }

    @formDisable(e)

    @ajax(
      id:          "vm-meta-comment-#{@mode}"
      type:        'POST'
      url:         url
      processData: true
      data:        JSON.stringify(data)
      success: (data) =>
        # Sent, but the note in the ticket failed: say so, or the agent assumes nothing went out.
        if data?.warning
          App.Event.trigger('notify', { type: 'warn', msg: App.i18n.translateContent(data.warning), timeout: 8000 })
        @close()
      error: (xhr) =>
        @formEnable(e)
        @showAlert(xhr.responseJSON?.error or __('Das hat nicht geklappt.'))
    )
