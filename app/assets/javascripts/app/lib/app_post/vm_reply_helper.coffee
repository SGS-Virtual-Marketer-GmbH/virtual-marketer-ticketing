# Turns an assistant draft into a real reply on a ticket.
#
# The assistant itself can neither send nor save anything to the customer; it
# hands back text. Everything here runs in the browser as the logged-in agent
# and goes through Zammad's own API, so ticket permissions apply exactly as for
# a reply typed by hand. A click on a button is the decision to send, never a
# tool the model can call (ticket text is attacker-controlled, so an assistant
# that could send would be one prompt injection from mailing a customer).
#
# Recipients, subject and quoting come from Zammad's own reply logic
# (App.Utils.getRecipientArticle), so a reply goes where the "Antworten" button
# in the ticket would send it. The group signature is added the same way the
# reply box does it.

class App.VmReplyHelper

  # Plain draft text -> HTML. Escaped first: the draft is model output that may
  # quote customer text, and App.Utils.text2html does not escape on its own.
  @textToHtml: (text) ->
    App.Utils.text2html(App.Utils.htmlEscape(String(text or '').replace(/\r\n/g, '\n').trim()))

  # Load the ticket with its articles and work out where a reply would go.
  # callback(error, context) with
  #   context = { ticket, article, to, cc, subject, inReplyTo, number, canMail }
  # canMail is false for tickets without an email channel (chat, phone-only),
  # where "senden" would mean something else entirely.
  @context: (ticketId, callback) ->
    App.Ajax.request(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets/#{ticketId}?all=true"
      processData: true
      success: (data) =>
        App.Collection.loadAssets(data.assets) if data.assets
        ticket = App.Ticket.fullLocal(ticketId)
        return callback('ticket') if !ticket

        articles = (App.TicketArticle.find(id) for id in (ticket.article_ids or []))
        articles = _.filter(articles, (a) -> a?)
        emailOf  = (a) -> App.TicketArticleType.find(a.type_id)?.name in ['email', 'web']
        senderOf = (a) -> App.TicketArticleSender.find(a.sender_id)?.name
        byId     = (a, b) -> a.id - b.id
        customerMails = _.filter(articles, (a) -> senderOf(a) is 'Customer' and emailOf(a)).sort(byId)
        anyMails      = _.filter(articles, (a) -> emailOf(a)).sort(byId)
        article = _.last(customerMails) or _.last(anyMails)

        return callback(null, { ticket, number: ticket.number, canMail: false }) if !article

        # getRecipientArticle reads article.sender.name and the like, so the
        # article has to be filled up with its relations first.
        article  = App.TicketArticle.fullLocal(article.id)
        type     = App.TicketArticleType.find(article.type_id)
        createdBy = App.User.find(article.created_by_id)
        recipient = App.Utils.getRecipientArticle(ticket, article, createdBy, type, App.EmailAddress.all(), false)

        callback(null, {
          ticket:    ticket
          article:   article
          number:    ticket.number
          to:        recipient.to
          cc:        recipient.cc
          inReplyTo: recipient.in_reply_to
          subject:   if _.isEmpty(article.subject) then ticket.title else article.subject
          canMail:   !_.isEmpty(recipient.to) and !!recipient.to.match(/@/)
        })
      error: (xhr) -> callback(xhr.status or 'error')
    )

  # The article attributes shared by "send" and "save as draft".
  @articleAttributes: (context, text) ->
    {
      type:        'email'
      internal:    false
      to:          context.to
      cc:          context.cc
      subject:     context.subject
      in_reply_to: context.inReplyTo
      content_type: 'text/html'
      body:        @textToHtml(text)
    }

  # Body with the group's signature appended, as the reply box would do it.
  @bodyWithSignature: (context, text) ->
    body   = @textToHtml(text)
    result = App.SignatureHelper.findForGroup(context.ticket.group_id)
    return body if !result
    rendered = App.SignatureHelper.render(result.signature.body, context.ticket)
    sig      = App.SignatureHelper.buildElement(result.signature.id, rendered)
    "#{body}<br><br>#{sig[0].outerHTML}"

  # POST the reply. This is the one place that mails a customer.
  @send: (context, text, callback) ->
    attrs = @articleAttributes(context, text)
    attrs.body      = @bodyWithSignature(context, text)
    attrs.ticket_id = context.ticket.id
    attrs.sender    = 'Agent'
    App.Ajax.request(
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/ticket_articles"
      data: JSON.stringify(attrs)
      processData: true
      success: (data) -> callback(null, data)
      error: (xhr) -> callback(xhr.status or 'error', xhr.responseJSON?.error or xhr.responseText)
    )

  # Park the reply as the ticket's shared draft. The agent sees "Entwurf
  # verfügbar" in the reply box and applies it with one click; nothing is sent.
  @saveDraft: (context, text, callback) ->
    App.Ajax.request(
      type: 'PUT'
      url:  "#{App.Config.get('api_path')}/tickets/#{context.ticket.id}/shared_draft"
      data: JSON.stringify(
        form_id:           App.ControllerForm.formId()
        new_article:       @articleAttributes(context, text)
        ticket_attributes: {}
      )
      processData: true
      success: (data) -> callback(null, data)
      error: (xhr) -> callback(xhr.status or 'error')
    )

  # Fill the open ticket's reply box (ticket zoom only). The signature is added
  # by the reply box itself on setArticleType.
  @fillReplyBox: (context, text) ->
    article = @articleAttributes(context, text)
    article.subtype = 'reply'
    App.Event.trigger('ui::ticket::setArticleType', {
      ticket:            context.ticket
      type:              App.TicketArticleType.findByAttribute(name: 'email')
      article:           article
      signaturePosition: 'bottom'
    })
