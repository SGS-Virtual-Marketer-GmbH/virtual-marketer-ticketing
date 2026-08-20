# The bridge between the ticketing UI and the Virtual Marketer assistant.
#
# This controller exists for one reason: to be the only place that can say who
# is asking. The browser posts a message and nothing else — no user id, no
# email, no token. Here the session already identifies the agent, so their
# address is signed and forwarded, and the assistant service accepts an identity
# only with a valid signature.
#
# Letting the browser name the user would mean any agent could chat as a
# colleague — read their tickets, write notes under their name — by editing one
# request. So the identity is taken from the session and never from params, and
# the signing secret stays on the server.
#
# The assistant then calls back into Zammad as this same user (the `From`
# header), which is what keeps group permissions intact end to end.

class VMAssistantController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # POST /api/v1/vm_assistant/chat
  def chat
    return render json: { error: __('Der Assistent ist nicht eingerichtet.') }, status: :service_unavailable if !configured?

    timestamp = (Time.current.to_f * 1000).to_i.to_s
    email     = current_user.email.to_s.downcase

    response = UserAgent.post(
      "#{assistant_url}/assistant/chat",
      {
        message:      params[:message].to_s,
        history:      params[:history] || [],
        ticketNumber: params[:ticket_number],
      },
      {
        headers:      {
          'X-VM-User'      => email,
          'X-VM-Timestamp' => timestamp,
          'X-VM-Signature' => signature(timestamp, email),
        },
        json:         true,
        open_timeout: 10,
        # The assistant may run several tool calls per message, each a round
        # trip to Zammad or Xentral. Anything under a minute cuts off answers
        # that were about to arrive.
        read_timeout: 90,
        total_timeout: 100,
      },
    )

    if !response.success?
      Rails.logger.error "VM assistant call failed: #{response.code} #{response.error}"
      return render json: { error: __('Der Assistent ist gerade nicht erreichbar.') }, status: :bad_gateway
    end

    render json: response.data
  end

  private

  def configured?
    assistant_url.present? && shared_secret.present?
  end

  def assistant_url
    @assistant_url ||= ENV['VM_ASSISTANT_URL'].to_s.sub(%r{/+$}, '')
  end

  def shared_secret
    @shared_secret ||= ENV['VM_ASSISTANT_SHARED_SECRET'].to_s
  end

  # Must match assistant/router.js#verifyCaller exactly. The timestamp is inside
  # the signed string so a captured request cannot be replayed indefinitely —
  # the other side rejects anything older than five minutes.
  def signature(timestamp, email)
    OpenSSL::HMAC.hexdigest('SHA256', shared_secret, "#{timestamp}.#{email}")
  end
end
