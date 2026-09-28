# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Handles Meta's webhook verification handshake (the GET request sent once
# when the callback URL + verify token are entered in the Meta App Dashboard).
module VmMeta::Webhook
  class Configuration
    include VmMeta::Webhook::Concerns::HasChannel

    def initialize(options:)
      @options = options
    end

    def verify!
      raise VerificationError if @options.blank?
      raise VerificationError if @options[:'hub.mode'] != 'subscribe'
      raise VerificationError if @options[:'hub.challenge'].blank?

      channel = find_channel!(@options[:callback_url_uuid])
      raise VerificationError if channel.options[:verify_token].blank?
      raise VerificationError if channel.options[:verify_token] != @options[:'hub.verify_token']

      @options[:'hub.challenge']
    end

    class VerificationError < StandardError
      def initialize
        super(__('The VmMeta channel webhook configuration could not be verified.'))
      end
    end
  end
end
