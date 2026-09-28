# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class VmMetaChannelSupport < ActiveRecord::Migration[7.0]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    # Reuses the existing 'admin.channel_facebook' permission (see
    # Controllers::ChannelsAdmin::VmMetaControllerPolicy) - no new permission
    # needed.

    Ticket::Article::Type.create_if_not_exists(
      name:          'messenger message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

    Ticket::Article::Type.create_if_not_exists(
      name:          'instagram message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end
end
