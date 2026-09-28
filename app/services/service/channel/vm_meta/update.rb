# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Service::Channel::VmMeta
  class Update < Base
    attr_reader :channel_id

    def initialize(params:, channel_id:)
      @channel_id = channel_id
      @params     = params
    end

    def options
      merged = channel.options.merge(params.slice(*PERMITTED_OPTION_KEYS))
      merged[:human_agent_tag] = ActiveModel::Type::Boolean.new.cast(merged[:human_agent_tag]) if params.key?(:human_agent_tag)

      merged
    end

    def execute
      ActiveRecord::Base.transaction do
        channel.update!(**attributes_hash)
      end

      channel
    end

    private

    def channel
      @channel ||= area_channel_list.find(channel_id)
    end
  end
end
