# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class VmMetaCommentSupport < ActiveRecord::Migration[7.0]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::Article::Type.create_if_not_exists(
      name:          'facebook comment',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

    Ticket::Article::Type.create_if_not_exists(
      name:          'instagram comment',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end
end
