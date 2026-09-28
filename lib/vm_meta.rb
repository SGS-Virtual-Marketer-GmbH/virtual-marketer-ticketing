# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Facebook Messenger / Instagram Direct channel ("VmMeta::Page").
#
# Modeled closely on the WhatsApp Business Cloud API channel (lib/whatsapp.rb,
# lib/whatsapp/*) - same shape: signed webhook in, one open ticket per
# customer conversation, a customer mapped from the platform's own contact id,
# a 24h/7d reply window, and a background delivery job with retries.
#
# Fixed naming (relied on by another codebase, do not rename):
#   - Article types: 'messenger message', 'instagram message'
#   - Channel area: 'VmMeta::Page'
#   - Channel adapter: 'vm_meta'
module VmMeta

  GRAPH_API_VERSION = 'v23.0'.freeze
  GRAPH_BASE_URL     = 'https://graph.facebook.com'.freeze

  MIME_TYPES = {
    'image/jpeg':                                                                'jpeg',
    'image/png':                                                                 'png',
    'image/gif':                                                                 'gif',
    'image/webp':                                                                'webp',

    'video/mp4':                                                                 'mp4',
    'video/quicktime':                                                           'mov',

    'audio/mpeg':                                                                'mp3',
    'audio/mp4':                                                                 'm4a',
    'audio/aac':                                                                 'aac',
    'audio/ogg':                                                                 'ogg',
    'audio/wav':                                                                 'wav',

    'application/pdf':                                                          'pdf',
    'text/plain':                                                                'txt',
    'application/msword':                                                       'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':  'docx',
    'application/vnd.ms-excel':                                                 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':        'xlsx',
  }.freeze

  # Meta's own attachment "type" values, as used both on incoming
  # (message.attachments[].type) and outgoing (message.attachment.type) payloads.
  DEFAULT_MIME_TYPE_BY_ATTACHMENT_TYPE = {
    'image' => 'image/jpeg',
    'audio' => 'audio/mpeg',
    'video' => 'video/mp4',
    'file'  => 'application/octet-stream',
  }.freeze

  def self.file_suffix(mime_type:)
    identified_mime_type = VmMeta::MIME_TYPES[mime_type.to_s.to_sym]
    return identified_mime_type if identified_mime_type.present?

    identified_mime_type = MIME::Types[mime_type]&.first
    return identified_mime_type.preferred_extension if identified_mime_type.present? && identified_mime_type.preferred_extension.present?

    'dat'
  end

  # Maps a MIME type onto Meta's coarse attachment "type" enum (image / audio
  # / video / file), used to build the outgoing attachment payload.
  def self.attachment_type(mime_type:)
    case mime_type.to_s
    when %r{\Aimage/}
      'image'
    when %r{\Aaudio/}
      'audio'
    when %r{\Avideo/}
      'video'
    else
      'file'
    end
  end
end
