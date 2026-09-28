class App.TicketZoomChannel

  constructor: (ticket) ->
    @ticket = ticket

  channelAlert: =>
    # Add a frontend module layer here for other channels, if the need arises.
    return @whatsappAlert() if _.has(@ticket.preferences, 'whatsapp')
    return @vmMetaAlert() if _.has(@ticket.preferences, 'vm_meta')
    null

  vmMetaAlert: =>
    lastTimestamp = @ticket.preferences.vm_meta.timestamp_incoming

    # In case no customer message was ever received yet, or the ticket is closed, hide the alert.
    return null if not lastTimestamp or /^(closed|merged|removed)$/.test(@ticket.state.name)

    # Meta's messaging.timestamp is epoch MILLISECONDS (unlike WhatsApp's
    # epoch seconds) - not verified against a live webhook in this
    # environment, re-check against a real payload.
    lastMessageDate = new Date(lastTimestamp)

    standardWindowEnd = new Date(lastMessageDate.getTime() + 24 * 60 * 60 * 1000)

    # Standard 24h window still open.
    if standardWindowEnd > new Date()
      return {
        text: __('You have a 24 hour window to reply in this conversation. The window closes %s.')
        textPlaceholder: App.ViewHelpers.humanTime(standardWindowEnd)
        noQuote: true
        type: 'warning'
      }

    # 24h window closed. If the channel allows it, a reply is still possible
    # for up to 7 days total, tagged as a human-agent reply.
    # 'human_agent_tag' is exposed on the ticket's own preferences at
    # creation time (see lib/vm_meta/webhook/message.rb's ticket_preferences)
    # since the frontend has no other way to know a channel-level setting.
    if @ticket.preferences.vm_meta.human_agent_tag
      humanAgentWindowEnd = new Date(lastMessageDate.getTime() + 7 * 24 * 60 * 60 * 1000)

      if humanAgentWindowEnd > new Date()
        return {
          text: __('The 24 hour window is closed. A reply is only possible with human-agent tagging, until %s.')
          textPlaceholder: App.ViewHelpers.humanTime(humanAgentWindowEnd)
          noQuote: true
          type: 'warning'
        }

    return {
      text: __('The 24 hour window is closed. A reply will only be possible again once the customer writes again.')
      type: 'danger'
    }

  whatsappAlert: =>
    lastWhatsappTimestamp = @ticket.preferences.whatsapp.timestamp_incoming

    # In case the customer service window is not open yet, or the ticket is closed, hide the alert.
    return null if not lastWhatsappTimestamp or /^(closed|merged|removed)$/.test(@ticket.state.name)

    # Determine the end of the customer service window and set the appropriate alert text and type.
    timeWindowEnd = new Date(lastWhatsappTimestamp * 1000)
    timeWindowEnd.setHours(timeWindowEnd.getHours() + 24)

    # If time window is already closed, return an error alert. A Meta-approved
    # template can still reopen the conversation, so the alert offers that
    # instead of just explaining the dead end -- see App.VmWhatsappTemplateModal.
    if timeWindowEnd <= new Date()
      return {
        text: __('The 24 hour customer service window is now closed, no further WhatsApp messages can be sent.')
        type: 'danger'
        showTemplateButton: true
      }

    # Otherwise, return a warning alert with a "humanized" end time of the window.
    return {
      text: __('You have a 24 hour window to send WhatsApp messages in this conversation. The customer service window closes %s.')
      textPlaceholder: App.ViewHelpers.humanTime(timeWindowEnd)
      noQuote: true
      type: 'warning'
    }
