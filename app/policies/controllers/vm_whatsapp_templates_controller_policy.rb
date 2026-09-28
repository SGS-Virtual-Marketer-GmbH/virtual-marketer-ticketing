class Controllers::VmWhatsappTemplatesControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required, not optional: `authenticate_and_authorize!` resolves the policy
  # through Pundit and raises NotDefinedError when there is none -- same rule
  # as VmAssistantControllerPolicy/VmCountsControllerPolicy.
  #
  # This only gates whether the endpoint can be hit at all. Each action also
  # authorizes against the specific ticket it was given (TicketPolicy#follow_up?,
  # the same check TicketArticlesController#create uses), because
  # 'ticket.agent' alone says nothing about whether THIS agent can see or
  # reply to THIS ticket's group.
  default_permit!('ticket.agent')
end
