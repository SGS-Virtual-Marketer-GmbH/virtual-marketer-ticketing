class Controllers::VmSenderAddressesControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required: `authenticate_and_authorize!` resolves the policy through Pundit
  # and raises NotDefinedError when there is none (same rule as
  # VmWhatsappTemplatesControllerPolicy). This only gates whether the endpoint
  # can be hit at all; the action also authorizes against the specific ticket
  # (TicketPolicy#follow_up?, the check TicketArticlesController#create uses).
  default_permit!('ticket.agent')
end
