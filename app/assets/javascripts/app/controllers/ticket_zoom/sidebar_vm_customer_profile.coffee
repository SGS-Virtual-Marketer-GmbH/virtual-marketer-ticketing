# The customer-context card as a ticket sidebar tab: who the customer is, how
# many times they have contacted us in total, their Xentral order history,
# and the order this ticket is most likely about — the things a care agent
# otherwise pieces together by hand across Zammad and Xentral.
#
# A tab next to "Customer"/"Organization", not an always-open panel: every
# section of this sidebar already works that way (see sidebar_customer.coffee,
# sidebar_organization.coffee), so this fits the existing UI instead of
# introducing a second pattern for one feature.
#
# Refetched every time the tab is opened rather than cached on the controller
# instance — order data and ticket counts change between visits, and a stale
# number shown confidently is worse than a moment's loading state.
#
# Agents only, same reasoning as the assistant tab (sidebar_vm_assistant.coffee):
# a customer logged into the portal has no business seeing our own assembled
# read of their order history.

class SidebarVMCustomerProfile extends App.Controller
  sidebarItem: =>
    return if !@ticket
    return if @ticket.currentView() isnt 'agent'

    @item = {
      name:            'vm-customer-profile'
      badgeIcon:       'person'
      sidebarHead:     __('Kundenprofil')
      sidebarCallback: @showProfile
    }
    @item

  showProfile: (el) =>
    @profile?.release?()
    @profile = new App.VmCustomerProfile(
      el:           el
      ticketNumber: @ticket.number
    )

# Sorted first (App.Sidebar picks the alphabetically-first tab as the default
# when nothing is remembered yet for this ticket) so Kundenprofil opens by
# default instead of the native "Bearbeiten" tab -- the customer context is
# what an agent needs on first glance, not last.
App.Config.set('050-VMCustomerProfile', SidebarVMCustomerProfile, 'TicketZoomSidebar')
