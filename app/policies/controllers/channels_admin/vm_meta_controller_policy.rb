# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Reuses the existing 'admin.channel_facebook' permission - there is no
# dedicated permission for this channel and the task explicitly calls for
# reusing this one rather than adding a new permission record.
class Controllers::ChannelsAdmin::VmMetaControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin.channel_facebook')
end
