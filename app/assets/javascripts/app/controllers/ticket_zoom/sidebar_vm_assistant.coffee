# The assistant as a ticket sidebar tab.
#
# Registering here rather than bolting a floating button onto the page is what
# gets the ticket context for free: the sidebar already knows which ticket is
# open, so "fasse das zusammen" works without anyone retyping a number, and the
# panel opens and closes with the same affordance as every other sidebar tab.
#
# Agents only. A customer logged into the portal has no business driving tools
# that read Xentral.

class SidebarVMAssistant extends App.Controller
  sidebarItem: =>
    return if !@ticket
    return if @ticket.currentView() isnt 'agent'

    @item = {
      name:            'vm-assistant'
      badgeIcon:       'logo'
      sidebarHead:     __('Assistent')
      sidebarCallback: @showAssistant
    }
    @item

  showAssistant: (el) =>
    @assistantEl = el
    # Rebuilding on every tab switch would throw away the conversation, which is
    # the one thing somebody mid-question would not forgive.
    if @assistant
      el.html(@assistant.el)
      return

    @assistant = new App.VmAssistant(
      el:           el
      ticketNumber: @ticket.number
    )

App.Config.set('400-VMAssistant', SidebarVMAssistant, 'TicketZoomSidebar')
