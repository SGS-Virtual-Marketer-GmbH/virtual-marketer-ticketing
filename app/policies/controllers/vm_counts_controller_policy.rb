class Controllers::VmCountsControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required: `authenticate_and_authorize!` resolves the policy through Pundit
  # and raises NotDefinedError without one. The counts are the agent's own
  # overviews, already limited to the groups they can see.
  default_permit!('ticket.agent')
end
