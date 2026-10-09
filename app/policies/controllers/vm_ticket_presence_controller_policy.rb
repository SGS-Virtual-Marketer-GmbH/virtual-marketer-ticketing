class Controllers::VmTicketPresenceControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required: `authenticate_and_authorize!` resolves the policy through Pundit.
  # The action itself only answers for tickets the viewer may read.
  default_permit!('ticket.agent')
end
