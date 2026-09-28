# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Service::Channel::VmMeta
  class Create < Base
    REQUIRED_FIELDS = %i[page_id page_access_token app_secret].freeze

    def initialize(params:)
      @params = params
    end

    def execute
      validate_required!

      ActiveRecord::Base.transaction do
        Channel.create!(
          area: area,
          **attributes_hash.merge(options: options.merge(initial_options)),
        )
      end
    end

    private

    def validate_required!
      missing = REQUIRED_FIELDS.select { |field| params[field].blank? }
      return if missing.empty?

      raise ArgumentError, "Missing required field(s): #{missing.join(', ')}"
    end

    def initial_options
      {
        adapter:           'vm_meta',
        callback_url_uuid: SecureRandom.uuid,
        verify_token:      SecureRandom.urlsafe_base64(24),
        human_agent_tag:   ActiveModel::Type::Boolean.new.cast(params[:human_agent_tag]) || false,
      }
    end
  end
end
