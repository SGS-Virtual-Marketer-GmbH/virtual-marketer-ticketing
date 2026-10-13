# Moderation of a customer's public Facebook/Instagram comment, as article
# actions on the comment itself: answer privately (a direct message that
# Meta ties to the comment, once, within 7 days) and hide/show the comment.
# The public answer stays the ordinary reply. See VmMetaCommentsController.
class VmMetaComment extends App.Controller
  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'
    return actions if article.type.name not in ['facebook comment', 'instagram comment']
    return actions if article.sender.name isnt 'Customer'

    actions.push {
      name: __('Privat antworten')
      type: 'vmMetaCommentPrivateReply'
      icon: 'email'
      href: '#'
    }
    actions.push {
      name: __('Kommentar verbergen')
      type: 'vmMetaCommentHide'
      icon: 'eye'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    if type is 'vmMetaCommentPrivateReply'
      new App.VmMetaCommentModal(ticket: ticket, mode: 'private')
      return true

    if type is 'vmMetaCommentHide'
      new App.VmMetaCommentModal(ticket: ticket, mode: 'hide')
      return true

    true

App.Config.set('320-VmMetaComment', VmMetaComment, 'TicketZoomArticleAction')
