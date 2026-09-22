# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class DentaCareAgentDuplicateContentCheck < ActiveRecord::Migration[6.0]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Defines postmaster filter.',
      name:        '0012_postmaster_filter_duplicate_content_check',
      area:        'Postmaster::PreFilter',
      description: 'Ignores a follow-up email that duplicates an article already on its ticket (mailbox reimport), instead of appending another copy.',
      options:     {},
      state:       'Channel::Filter::DuplicateContentCheck',
      frontend:    false
    )
  end
end
