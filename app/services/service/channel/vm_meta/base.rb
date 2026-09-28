# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Service::Channel::VmMeta
  class Base < Service::Base
    attr_reader :params

    PERMITTED_OPTION_KEYS = %i[page_id page_access_token app_secret instagram_account_id human_agent_tag name].freeze

    private

    def area
      'VmMeta::Page'.freeze
    end

    def area_channel_list
      Channel.in_area(area)
    end

    def attributes_hash
      {
        group_id:,
        options:,
      }
    end

    def group_id
      params[:group_id]
    end

    def options
      params.slice(*PERMITTED_OPTION_KEYS)
    end
  end
end
