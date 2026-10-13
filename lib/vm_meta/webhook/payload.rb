# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module VmMeta::Webhook
  class Payload
    include VmMeta::Webhook::Concerns::HasChannel

    # object => which channel option carries the matching id for entry[].id
    OBJECT_ID_OPTION = {
      'page'      => :page_id,
      'instagram' => :instagram_account_id,
    }.freeze

    OBJECT_PLATFORM = {
      'page'      => 'messenger',
      'instagram' => 'instagram',
    }.freeze

    def initialize(json:, uuid:, signature:)
      @channel = find_channel!(uuid)

      raise SignatureError if !valid_signature?(json:, signature:)

      @data = JSON.parse(json).deep_symbolize_keys
    end

    def process
      raise ProcessableError, __('Unsupported webhook object.') if !supported_object?
      raise ProcessableError, __('Mismatching page/account id.') if !entries_match_channel?

      entries.each do |entry|
        Array(entry[:messaging]).each { |event| process_event(entry:, event:) }
        Array(entry[:changes]).each { |change| process_change(entry:, change:) }
      end
    end

    private

    # Signature must be checked against the RAW body, before any JSON
    # parsing happens - constant-time compare so this can't be used as a
    # timing oracle for the app secret.
    def valid_signature?(json:, signature:)
      return false if signature.blank?

      secret = @channel.options[:app_secret]
      return false if secret.blank?

      digest   = OpenSSL::Digest.new('sha256')
      expected = OpenSSL::HMAC.hexdigest(digest, secret, json)

      return false if expected.bytesize != signature.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def supported_object?
      OBJECT_ID_OPTION.key?(@data[:object].to_s)
    end

    def platform
      OBJECT_PLATFORM.fetch(@data[:object].to_s)
    end

    def entries
      Array(@data[:entry])
    end

    def entries_match_channel?
      expected_id = @channel.options[OBJECT_ID_OPTION.fetch(@data[:object].to_s)].to_s
      return false if expected_id.blank?

      entries.all? { |entry| entry[:id].to_s == expected_id }
    end

    def process_event(entry:, event:)
      return log_ignored('echo')     if event.dig(:message, :is_echo)
      return log_ignored('delivery') if event.key?(:delivery)
      return log_ignored('read')     if event.key?(:read)
      return log_ignored('reaction') if event.key?(:reaction)
      return log_ignored('postback') if event.key?(:postback)
      return if !event.key?(:message)

      sender_id = event.dig(:sender, :id).to_s
      return if sender_id.blank?
      # Never process a message the page/IG account sent to itself.
      return if sender_id == entry[:id].to_s

      VmMeta::Webhook::Message.new(
        data:     event,
        page_id:  entry[:id].to_s,
        channel:  @channel,
        platform:,
      ).process
    end

    # Public comments arrive as 'changes' (Page field 'feed', Instagram field
    # 'comments'), not as 'messaging'. Isolated on purpose: whatever goes wrong
    # with a comment must never fail the webhook, because Meta would then
    # redeliver - and starve - the direct messages in the same payload.
    def process_change(entry:, change:)
      value = change[:value]
      return if !value.is_a?(Hash)

      comment_platform = comment_platform_of(change)
      return log_ignored("change #{change[:field]}") if comment_platform.nil?

      VmMeta::Webhook::Comment.new(
        value:,
        page_id:  entry[:id].to_s,
        channel:  @channel,
        platform: comment_platform,
      ).process
    rescue => e
      Rails.logger.error "VmMeta channel (#{@channel.options[:callback_url_uuid]}) - comment processing failed: #{e.class}: #{e.message}"
    end

    def comment_platform_of(change)
      value = change[:value]

      case [@data[:object].to_s, change[:field].to_s]
      when %w[page feed]
        'facebook' if value[:item].to_s == 'comment' && value[:verb].to_s == 'add'
      when %w[instagram comments]
        'instagram'
      end
    end

    def log_ignored(kind)
      Rails.logger.debug { "VmMeta channel (#{@channel.options[:callback_url_uuid]}) - ignored '#{kind}' webhook event" }
    end

    class SignatureError < StandardError
      def initialize
        super(__('The VmMeta webhook payload signature could not be validated.'))
      end
    end

    class ProcessableError < StandardError
      attr_reader :reason

      def initialize(reason = nil)
        @reason = reason
        super(__('The VmMeta webhook payload could not be processed.'))
      end
    end
  end
end
