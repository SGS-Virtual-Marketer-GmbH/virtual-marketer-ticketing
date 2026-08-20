class Controllers::VMAssistantControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required, not optional: `authenticate_and_authorize!` resolves the policy
  # through Pundit, and Pundit raises NotDefinedError when there is none — so
  # without this file the endpoint fails for everybody, admins included.
  #
  # The assistant reads tickets, writes internal notes and changes states. That
  # is agent work, so agents are the audience; a customer holds ticket.customer
  # and is kept out here rather than relying on the assistant service to notice.
  default_permit!('ticket.agent')
end
