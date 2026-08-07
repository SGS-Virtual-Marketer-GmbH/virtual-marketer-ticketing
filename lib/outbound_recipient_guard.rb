# Restrict who this instance may send email to.
#
# Configured with OUTBOUND_EMAIL_DOMAIN_ALLOWLIST, a comma-separated list of
# domains. Unset or empty means no restriction, which is upstream's behaviour —
# so this is inert on any deployment that does not opt in.
#
# Why this exists
# ---------------
# DentaTec's Zendesk history was imported here: ~2,000 tickets whose customers
# were answered months ago, on a system that is not yet the one handling their
# mail. Every one of them has a real, working customer address attached. An
# agent exploring the new helpdesk and pressing reply on an imported ticket
# would send a live email to that customer about a case they consider closed.
#
# An environment variable rather than a Setting, deliberately: a safety guard
# for a system in parallel operation should not be switchable from the same
# admin UI the people being guarded are working in, and it needs no migration
# to reach an already-initialised instance.
#
# Enforced at two points, because they are the two ways mail leaves:
#   - TicketArticleCommunicateEmailJob — agent replies and AI auto-replies
#   - NotificationFactory::Mailer.deliver — trigger and system notifications
#
# Both report the block rather than dropping silently: a reply that looks sent
# but was not is worse than one that clearly failed.
module OutboundRecipientGuard
  ENV_KEY = 'OUTBOUND_EMAIL_DOMAIN_ALLOWLIST'.freeze

  class << self
    # @return [Array<String>] lower-cased domains, empty when unrestricted
    def allowed_domains
      @allowed_domains ||= ENV[ENV_KEY].to_s.split(%r{[,\s]+}).filter_map do |d|
        cleaned = d.strip.downcase.delete_prefix('@')
        cleaned.presence
      end
    end

    def active?
      allowed_domains.any?
    end

    # @param address [String] one address, or a comma-separated list, or a
    #   full "Name <addr@example.com>" form as stored on an article
    # @return [Array<String>] the addresses that may NOT be written to
    def blocked(*addresses)
      return [] if !active?

      extract(addresses).reject { |addr| permitted?(addr) }
    end

    # A domain matches itself and any subdomain of it, so a customer served
    # from mail.denta-tec.com is not blocked on a technicality.
    def permitted?(address)
      return true if !active?

      domain = address.to_s.downcase.split('@').last.to_s
      return false if domain.blank?

      allowed_domains.any? { |allowed| domain == allowed || domain.end_with?(".#{allowed}") }
    end

    def describe
      "nur #{allowed_domains.join(', ')} (#{ENV_KEY})"
    end

    # Test seam — the env var is read once and memoised.
    def reset!
      @allowed_domains = nil
    end

    private

    def extract(values)
      values.flatten.compact.flat_map { |v| v.to_s.split(',') }
            .filter_map { |part| part[%r{[^\s<>,;]+@[^\s<>,;]+}] }
            .uniq
    end
  end
end
