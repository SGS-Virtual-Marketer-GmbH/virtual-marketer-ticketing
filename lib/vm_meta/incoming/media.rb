# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Downloads an incoming Messenger/Instagram attachment from the (already
# public, pre-authenticated) URL Meta hands us in
# message.attachments[].payload.url - unlike WhatsApp there is no separate
# media-id lookup step, the URL is directly fetchable.
class VmMeta::Incoming::Media

  def download(url:, attachment_type:)
    result = UserAgent.get(url, {}, { open_timeout: 15, read_timeout: 60 })

    raise DownloadError, "HTTP #{result.code}" if !result.success?

    mime_type = result.content_type.to_s.split(';').first.presence || VmMeta::DEFAULT_MIME_TYPE_BY_ATTACHMENT_TYPE[attachment_type.to_s] || 'application/octet-stream'
    filename  = build_filename(attachment_type:, mime_type:)

    [result.body, filename, mime_type]
  end

  private

  def build_filename(attachment_type:, mime_type:)
    "#{attachment_type}-#{SecureRandom.hex(6)}.#{VmMeta.file_suffix(mime_type:)}"
  end

  class DownloadError < StandardError; end
end
