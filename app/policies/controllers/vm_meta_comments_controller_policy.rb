class Controllers::VmMetaCommentsControllerPolicy < Controllers::ApplicationControllerPolicy
  # Required, see VmSenderAddressesControllerPolicy. The actions authorize
  # against the specific ticket (follow_up?) themselves.
  default_permit!('ticket.agent')
end
