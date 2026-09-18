# Turns the AI pipeline's own drafted reply into two one-click actions on its
# internal note, instead of "select the paragraph, copy, click reply, paste,
# delete the greeting Zammad already inserted" -- go-live feedback
# 2026-09-18.
#
# Reuses App.VmPipelineNote (the same parser the VM workspace tile view uses
# for its own copy-to-clipboard button) rather than re-parsing the note text
# here -- one place that knows the note's block format.
#
# Mirrors EmailReply's own @action/@perform shape: this is the supported way
# to add a per-article action in this fork, with `ui` (the
# TicketZoomArticleActions instance) already providing scrollToCompose() and
# notify() -- no reaching into the compose editor's DOM from outside that
# framework.
class VmAntwortvorschlag extends App.Controller
  @action: (actions, ticket, article, ui) ->
    return actions if !article.internal

    note  = App.VmPipelineNote.from([article])
    draft = note?.draft()
    return actions if !draft

    actions.push {
      name: __('Antwortvorschlag kopieren')
      type: 'vmCopyAntwortvorschlag'
      icon: 'clipboard'
      href: '#'
    }
    actions.push {
      name: __('Antwortvorschlag übernehmen')
      type: 'vmUseAntwortvorschlag'
      icon: 'reply'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'vmCopyAntwortvorschlag' and type isnt 'vmUseAntwortvorschlag'

    note  = App.VmPipelineNote.from([article])
    draft = note?.draft()
    return true if !draft

    if type is 'vmCopyAntwortvorschlag'
      @copy(draft, ui)
    else
      @useAsReply(draft, ticket, ui)

    true

  @copy: (text, ui) ->
    done   = -> ui.notify(type: 'success', msg: __('Antwortvorschlag kopiert.'))
    failed = -> ui.notify(type: 'error', msg: __('Kopieren nicht möglich — bitte den Text markieren und selbst kopieren.'))

    if navigator.clipboard?.writeText
      navigator.clipboard.writeText(text).then(done, failed)
    else
      failed()

  # Same mechanism EmailReply uses to hand a body to the compose editor
  # (App.Event 'ui::ticket::setArticleType') -- switches the active editor to
  # 'email' if it wasn't already, so the drafted text lands somewhere that
  # can actually be sent, not silently into a still-open internal note.
  @useAsReply: (text, ticket, ui) ->
    ui.scrollToCompose()

    body = ("<div>#{_.escape(paragraph)}</div>" for paragraph in text.split('\n')).join('')

    type = App.TicketArticleType.findByAttribute(name: 'email')
    App.Event.trigger('ui::ticket::setArticleType', {
      ticket:  ticket
      type:    type
      article: { body: body, subtype: 'reply' }
    })

App.Config.set('210-VmAntwortvorschlag', VmAntwortvorschlag, 'TicketZoomArticleAction')
