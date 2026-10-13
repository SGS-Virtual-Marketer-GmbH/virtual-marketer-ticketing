# Which channel did this ticket come in on, at a glance.
#
# E-mail is the normal case and gets no chip: a label on every row would only
# be noise. The chat channels do get one, because they answer differently
# (WhatsApp window, Instagram text only, comments are public) and an agent
# should know before opening the ticket. The channel is the type of the
# ticket's first article (create_article_type_id), which every ticket has.

class App.VmChannel

  @CHANNELS:
    'whatsapp message':  { key: 'whatsapp',  label: __('WhatsApp') }
    'messenger message': { key: 'facebook',  label: __('Facebook') }
    'instagram message': { key: 'instagram', label: __('Instagram') }
    'facebook comment':  { key: 'facebook',  label: __('Facebook-Kommentar') }
    'instagram comment': { key: 'instagram', label: __('Instagram-Kommentar') }

  # { key, label } of the ticket's chat channel, or null (e-mail and the rest).
  @of: (ticket) ->
    typeId = ticket?.create_article_type_id
    return null if !typeId or !App.TicketArticleType.exists(typeId)
    @CHANNELS[App.TicketArticleType.find(typeId).name] or null

  @chip: (channel) ->
    return '' if !channel
    label = App.i18n.translateContent(channel.label)
    "<span class=\"vm-chan vm-chan--#{channel.key}\" title=\"#{label}\">#{label}</span>"
