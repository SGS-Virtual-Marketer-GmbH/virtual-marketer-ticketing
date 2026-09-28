# Once WhatsApp's 24 hour customer service window has closed, WhatsappReply
# hides the normal "reply" action (see its own @canUseWhatsapp) because a
# free-form reply would just be rejected by Meta. This is the replacement
# action for that state: open App.VmWhatsappTemplateModal so the agent can
# pick an approved template and re-open the conversation.
#
# Mirrors WhatsappReply's own @action/@perform shape -- the supported way to
# add a per-article action in this fork (see also VmAntwortvorschlag).
class VmWhatsappTemplate extends App.Controller
  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'
    return actions if article.type.name isnt 'whatsapp message'
    return actions if !@windowClosed(ticket)

    actions.push {
      name: __('Vorlage senden')
      type: 'vmSendWhatsappTemplate'
      icon: 'whatsapp'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'vmSendWhatsappTemplate'

    new App.VmWhatsappTemplateModal(ticket: ticket)

    true

  @windowClosed: (ticket) ->
    alert = new App.TicketZoomChannel(ticket).channelAlert()
    alert?.type is 'danger'

App.Config.set('310-VmWhatsappTemplate', VmWhatsappTemplate, 'TicketZoomArticleAction')
