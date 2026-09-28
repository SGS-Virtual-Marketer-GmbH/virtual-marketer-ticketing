# Facebook Messenger / Instagram Direct reply action + composer article type,
# modeled directly on WhatsappReply (whatsapp_reply.coffee) - same shape, one
# class covering both new article types ('messenger message' /
# 'instagram message') since they only differ in a handful of limits.
class VmMetaReply

  # Icons: 'facebook' reuses the existing sprite icon (no dedicated
  # "Messenger" glyph exists in it); Instagram deliberately has no sprite
  # icon reference here - the sprite itself is not touched for this feature,
  # see App.VmStatIcons/@VmIcon (vm_stat_icons.coffee) for where its inline
  # SVG lives instead (used by the article view badge, not this dropdown).
  @TYPE_CONFIG:
    'messenger message':
      actionType:   'vmMetaMessengerReply'
      icon:         'facebook'
      maxTextLength: 2000
      attachments:  true
    'instagram message':
      actionType:   'vmMetaInstagramReply'
      icon:         'instagram'
      maxTextLength: 1000
      attachments:  false

  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'

    config = VmMetaReply.TYPE_CONFIG[article.type.name]
    return actions if !config
    return actions if !@canUseVmMeta(ticket)

    actions.push {
      name: __('reply')
      type: config.actionType
      icon: 'reply'
      href: '#'
    }

    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    matchedTypeName = _.findKey(VmMetaReply.TYPE_CONFIG, (config) -> config.actionType is type)
    return true if !matchedTypeName

    ui.scrollToCompose()

    articleType = App.TicketArticleType.findByAttribute('name', matchedTypeName)

    articleNew = {
      to:          ''
      cc:          ''
      body:        ''
      in_reply_to: ''
    }

    App.Event.trigger('ui::ticket::setArticleType', {
      ticket: ticket
      type: articleType
      article: articleNew
    })

    true

  @articleTypes: (articleTypes, ticket, ui) ->
    return articleTypes if ticket.currentView() is 'customer'
    return articleTypes if !ticket || !ticket.create_article_type_id
    return articleTypes if !@canUseVmMeta(ticket)

    articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id).name
    config = VmMetaReply.TYPE_CONFIG[articleTypeCreate]
    return articleTypes if !config

    entry = {
      name:              articleTypeCreate
      icon:              config.icon
      attributes:        []
      internal:          false,
      features:          ['body:limit']
      maxTextLength:     config.maxTextLength
      warningTextLength: -1
    }

    if config.attachments
      entry.features.push('attachment', 'attachments:limit', 'attachments:size')
      entry.attachmentsLimit = 1
      entry.attachmentsSize  = [
        {
          size:          25 * 1024 * 1024
          label:         __('File')
          content_types: ['image/jpeg', 'image/png', 'image/gif', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'video/mp4', 'video/quicktime', 'application/pdf', 'text/plain', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
        },
      ]

    articleTypes.push entry
    articleTypes

  @params: (type, params, ui) ->
    if VmMetaReply.TYPE_CONFIG[type]
      App.Utils.htmlRemoveRichtext(ui.$('[data-name=body]'), false)
      params.content_type = 'text/plain'
      params.body = App.Utils.html2text(params.body, true)

    params

  @canUseVmMeta: (ticket) ->
    alert = new App.TicketZoomChannel(ticket).channelAlert()

    alert?.type and alert.type != 'danger'

App.Config.set('300-VmMetaReply', VmMetaReply, 'TicketZoomArticleAction')
