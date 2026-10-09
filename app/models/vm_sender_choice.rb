# Choose which system address an outgoing email is sent from.
#
# Without any choice, an agent's reply leaves from the email address of the
# ticket's group (Ticket::Article::AddsMetadataEmail). This is the one place
# that decides which OTHER addresses an agent may pick instead, so the list
# shown in the reply box (VmSenderAddressesController) and the check on the
# server (AddsMetadataEmail) cannot drift apart.
#
# The rule is deliberately narrow: an address may be chosen only if it is an
# active EmailAddress record of this system whose channel is active and can
# send. Free text is never accepted. The mail is then sent through exactly the
# channel that owns the chosen address, which TicketArticleCommunicateEmailJob
# already does for any article carrying preferences['email_address_id'].
class VmSenderChoice
  # Article preference the client sends to ask for another sender.
  PREFERENCE_KEY = 'vm_sender_email_address_id'.freeze

  # Channel areas that can deliver outgoing email.
  OUTBOUND_AREAS = %w[
    Email::Account
    Email::Notification
    Google::Account
    Microsoft365::Account
  ].freeze

  # Whether outgoing mail may be sent from this address.
  def self.usable?(email_address)
    return false if email_address.blank?
    return false if !email_address.active
    return false if email_address.channel_id.blank?

    channel = email_address.channel
    return false if channel.blank?
    return false if !channel.active

    OUTBOUND_AREAS.include?(channel.area)
  end

  # The addresses an agent may send from for a ticket of this group. The
  # group's own address always comes first (the default, and what is used when
  # nothing is chosen). Any further address is appended only if it is usable.
  def self.choices_for(group)
    default = group&.email_address
    others  = EmailAddress
      .where(active: true)
      .where.not(channel_id: nil)
      .includes(:channel)
      .order(:name, :email)
      .select { |address| address.id != default&.id && usable?(address) }

    [default, *others].compact
  end

  # Returns the address a new email article must be sent from. A blank request
  # or the group's own address means "as before". Anything else must be one of
  # the usable addresses, otherwise the request is refused instead of silently
  # sending from a different address than the agent saw.
  def self.resolve(group, requested_id)
    default = group&.email_address
    return default if requested_id.blank?
    return default if default && default.id.to_s == requested_id.to_s

    chosen = EmailAddress.find_by(id: requested_id.to_s.to_i) if requested_id.to_s.match?(%r{\A\d+\z})
    if !usable?(chosen)
      raise Exceptions::UnprocessableContent, __('Die gewählte Absenderadresse steht nicht zur Verfügung.')
    end

    chosen
  end
end
