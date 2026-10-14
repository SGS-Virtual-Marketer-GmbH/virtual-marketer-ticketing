class Controllers::VmCustomerHistoryControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required: `authenticate_and_authorize!` resolves the policy through Pundit.
  # Every agent gets the timeline; the action itself hands out content and ids
  # only for tickets the viewer may read.
  default_permit!('ticket.agent')
end
