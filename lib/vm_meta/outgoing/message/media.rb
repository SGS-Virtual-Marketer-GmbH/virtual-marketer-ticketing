# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Messenger-only. Instagram Direct's Send API only accepts a public URL for
# outbound attachments, not a file upload - since our stored attachments have
# no public URL, sending one on Instagram is rejected outright with a clear
# German error rather than silently failing against the Graph API.
class VmMeta::Outgoing::Message::Media < VmMeta::Outgoing::Message
  def deliver(attachment:, body: nil)
    raise InstagramAttachmentError, 'Instagram Direct unterstützt keine Datei-Anhänge in ausgehenden Nachrichten (nur öffentlich erreichbare URLs werden akzeptiert). Bitte den Anhang als Link senden oder per Messenger/E-Mail bereitstellen.' if platform == 'instagram'

    mime_type       = attachment.preferences['Mime-Type'] || attachment.preferences['Content-Type'] || 'application/octet-stream'
    attachment_type = VmMeta.attachment_type(mime_type:)

    fields = {
      recipient: { id: recipient_id }.to_json,
      message:   { attachment: { type: attachment_type, payload: { is_reusable: false } } }.to_json,
    }.merge(messaging_type_params.transform_values(&:to_s))

    response = client.post_multipart(
      "#{page_id}/messages",
      fields:,
      file_content: attachment.content,
      filename:     attachment.filename,
      mime_type:,
    )

    { id: response['message_id'] }
  end

  class InstagramAttachmentError < StandardError
    def retryable?
      false
    end
  end
end
