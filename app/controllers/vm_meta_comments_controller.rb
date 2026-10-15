# Moderation of a customer's public Facebook/Instagram comment, from the ticket.
#
#   POST /api/v1/vm_meta_comments/:ticket_id/hide          { hidden: true|false }
#   POST /api/v1/vm_meta_comments/:ticket_id/private_reply { body: "..." }
#
# Both act on the thread's LATEST customer comment. Meta allows exactly one
# private reply per comment, so the answer's id is kept on that article and a
# second attempt is refused here. What was done is written as an internal note,
# with the agent's name.
#
# Zeitwerk derives the constant from the filename -- "VmMetaComments", not "VMMeta".
class VmMetaCommentsController < ApplicationController
  # Messenger's own text limit; a longer body would only come back as a Graph error.
  PRIVATE_REPLY_MAX_LENGTH = 2000

  prepend_before_action :authenticate_and_authorize!

  def hide
    ticket, comment = load_comment!
    hidden          = ActiveModel::Type::Boolean.new.cast(params.fetch(:hidden, true))

    moderation(ticket).hide(comment_id: comment.message_id, hidden:)
    note(ticket, hidden ? __('Kommentar wurde verborgen.') : __('Kommentar wird wieder angezeigt.'))

    render json: { ok: true, hidden: }
  rescue => e
    fail_with(e)
  end

  def private_reply
    ticket, comment = load_comment!
    body            = params[:body].to_s.strip

    return render json: { error: __('Bitte einen Text eingeben.') }, status: :unprocessable_entity if body.blank?
    return render json: { error: __('Der Text ist zu lang für eine private Antwort.') }, status: :unprocessable_entity if body.length > PRIVATE_REPLY_MAX_LENGTH

    if comment.created_at < VmMeta::Outgoing::CommentModeration::PRIVATE_REPLY_WINDOW.ago
      return render json: { error: __('Der Kommentar ist älter als 7 Tage. Meta erlaubt dann keine private Antwort mehr.') }, status: :unprocessable_entity
    end

    # The row lock makes "already answered?" and "answer + remember it" one step:
    # two quick clicks (or two tabs) used to both pass the check and both send.
    already_answered = false
    comment.with_lock do
      if comment.preferences[:vm_meta_private_reply].present?
        already_answered = true
      else
        result      = moderation(ticket).private_reply(comment_id: comment.message_id, body:)
        preferences = comment.preferences
        preferences[:vm_meta_private_reply] = { id: result[:id], at: Time.zone.now.iso8601, by: current_user.id }
        comment.update_columns(preferences:) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    return render json: { error: __('Auf diesen Kommentar wurde schon privat geantwortet. Meta erlaubt nur eine private Antwort pro Kommentar.') }, status: :unprocessable_entity if already_answered

    # The message is out at this point. A failing note must not turn that into an
    # error, or the agent clicks again believing nothing was sent.
    begin
      note(ticket, "#{__('Private Antwort gesendet')}:\n#{body}")
    rescue => e
      Rails.logger.error "VmMetaCommentsController: private reply sent, note failed: #{e.class}: #{e.message}"
      return render json: { ok: true, warning: __('Die Antwort wurde gesendet, die Notiz im Ticket konnte aber nicht gespeichert werden.') }
    end

    render json: { ok: true }
  rescue => e
    fail_with(e)
  end

  private

  def load_comment!
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :follow_up?)

    raise __('Dieses Ticket ist kein Kommentar-Ticket.') if ticket.preferences[:vm_meta_comment].blank?

    comment = ticket.articles.where(type_id: comment_type_ids, sender_id: Ticket::Article::Sender.lookup(name: 'Customer').id).reorder(:id).last
    raise __('Es wurde kein Kommentar gefunden.') if comment.blank?

    [ticket, comment]
  end

  def comment_type_ids
    VmMeta::COMMENT_TYPES.map { |name| Ticket::Article::Type.lookup(name:).id }
  end

  def channel_for(ticket)
    channel = Channel.find_by(id: ticket.preferences[:channel_id])
    raise __('Der Kanal des Tickets wurde nicht gefunden.') if channel.blank?

    channel
  end

  def moderation(ticket)
    VmMeta::Outgoing::CommentModeration.new(options: channel_for(ticket).options, platform: ticket.preferences.dig(:vm_meta_comment, :platform))
  end

  def note(ticket, text)
    Ticket::Article.create!(
      ticket_id:    ticket.id,
      content_type: 'text/plain',
      body:         "#{text}\n(#{current_user.fullname})",
      internal:     true,
      sender:       Ticket::Article::Sender.find_by(name: 'Agent'),
      type:         Ticket::Article::Type.find_by(name: 'note'),
    )
  end

  # The Graph error text is German-safe to show to an agent, but never carries
  # a token (VmMeta::Graph::Client sanitises it).
  def fail_with(error)
    Rails.logger.error "VmMetaCommentsController: #{error.class}: #{error.message}"
    status = error.is_a?(Pundit::NotAuthorizedError) || error.is_a?(Exceptions::Forbidden) ? :forbidden : :unprocessable_entity
    render json: { error: error.message }, status:
  end
end
