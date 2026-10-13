# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Turns one public Facebook/Instagram comment (a 'changes' event, not a
# 'messaging' one) into a customer, a ticket and an article.
#
# One ticket per comment THREAD: a top-level comment and every reply below it
# share the ticket, so an agent sees the whole conversation under the post.
# The thread is identified by its root comment id (Facebook: the comment whose
# parent is the post; Instagram: the comment without parent).
#
# Deliberately separate from VmMeta::Webhook::Message:
#   - a comment has no reply window and no PSID; it is answered in public
#   - the ticket carries preferences['vm_meta_comment'], never 'vm_meta', so
#     none of the direct-message logic (24h window, send API) can ever apply
#   - a commenter's id is NOT assumed to equal a PSID, so no contact_ref
class VmMeta::Webhook::Comment

  POST_EXCERPT_LENGTH = 500

  attr_reader :value, :page_id, :channel, :platform, :user, :ticket, :article

  def initialize(value:, page_id:, channel:, platform:)
    @value    = value
    @page_id  = page_id
    @channel  = channel
    @platform = platform
  end

  def process
    return if comment_id.blank? || text_or_media.blank?
    # The page's/IG account's own comments (our replies coming back).
    return if author_id.blank? || author_id == page_id
    # Redelivery safety.
    return if Ticket::Article.exists?(message_id: comment_id)

    @user = create_or_update_user
    UserInfo.current_user_id = user.id

    @ticket  = find_ticket
    @ticket  = @ticket ? update_ticket(@ticket) : create_ticket
    @article = create_article

    add_post_context_note if @new_ticket

    ticket
  end

  private

  def facebook?
    platform == 'facebook'
  end

  def comment_id
    (facebook? ? value[:comment_id] : value[:id]).to_s
  end

  def parent_id
    value[:parent_id].to_s
  end

  def post_id
    (facebook? ? value[:post_id] : value.dig(:media, :id)).to_s
  end

  def text
    (facebook? ? value[:message] : value[:text]).to_s
  end

  def text_or_media
    return text if text.present?

    # A photo/video comment without text still deserves a ticket.
    facebook? && (value[:photo].presence || value[:video].presence) ? '(Kommentar ohne Text)' : nil
  end

  def author_id
    value.dig(:from, :id).to_s
  end

  def author_name
    name = facebook? ? value.dig(:from, :name) : value.dig(:from, :username)
    name.presence || default_name
  end

  def default_name
    facebook? ? 'Facebook-Nutzer' : 'Instagram-Nutzer'
  end

  # Facebook: a reply to a reply has the top-level comment as parent, a
  # top-level comment has the post as parent. Instagram: no parent = root.
  def root_id
    @root_id ||= if facebook?
                   parent_id.blank? || parent_id == post_id ? comment_id : parent_id
                 else
                   parent_id.presence || comment_id
                 end
  end

  def login
    prefix = facebook? ? 'meta-fbcomment' : 'meta-igcomment'

    "#{prefix}-#{page_id}-#{author_id}"
  end

  def create_or_update_user
    existing = User.find_by(login: login)
    return existing if existing

    firstname, lastname = User.name_guess(author_name)

    User.create!(
      login:       login,
      firstname:   firstname.presence || author_name,
      lastname:    lastname.presence || '',
      active:      true,
      role_ids:    Role.signup_role_ids,
      preferences: { vm_meta: { comment_author_id: author_id } },
    )
  end

  def display_name
    name = "#{user.firstname} #{user.lastname}".strip
    name.presence || author_name
  end

  def find_ticket
    candidate = Ticket::Article.find_by(message_id: root_id)&.ticket
    candidate = thread_ticket_of_customer if candidate.nil?

    return if candidate.nil?
    return if candidate.preferences[:channel_id] != channel.id
    return if %w[merged removed].include?(candidate.state.name)

    candidate
  end

  # The thread's root can be the page's own comment (no article), so fall back
  # to the thread id kept on the ticket itself.
  def thread_ticket_of_customer
    Ticket.where(customer_id: user.id).reorder(updated_at: :desc).limit(50).find do |possible|
      possible.preferences.dig(:vm_meta_comment, :thread_id).to_s == root_id
    end
  end

  def create_ticket
    @new_ticket = true

    Ticket.create!(
      group_id:    channel.group_id,
      title:       ticket_title,
      state_id:    Ticket::State.find_by(default_create: true).id,
      priority_id: Ticket::Priority.find_by(default_create: true).id,
      customer_id: user.id,
      preferences: {
        channel_id:      channel.id,
        channel_area:    channel.area,
        vm_meta_comment: ticket_preferences,
      },
    )
  end

  def ticket_title
    "#{facebook? ? 'Facebook' : 'Instagram'}-Kommentar von #{display_name}"
  end

  def ticket_preferences
    post = post_context

    {
      platform:,
      page_id:,
      thread_id: root_id,
      post_id:,
      post:,
    }.compact
  end

  def update_ticket(ticket)
    state = ticket.state_id == Ticket::State.find_by(default_create: true).id ? ticket.state : Ticket::State.find_by(default_follow_up: true)
    ticket.update!(state_id: state.id) if ticket.state_id != state.id

    ticket
  end

  def create_article
    Ticket::Article.create!(
      ticket_id:    ticket.id,
      type_id:      Ticket::Article::Type.lookup(name: article_type_name).id,
      sender_id:    Ticket::Article::Sender.lookup(name: 'Customer').id,
      from:         display_name,
      to:           channel.options[:name].to_s,
      message_id:   comment_id,
      internal:     false,
      body:         text_or_media,
      content_type: 'text/plain',
    )
  end

  def article_type_name
    facebook? ? 'facebook comment' : 'instagram comment'
  end

  # The post tells the agent what the comment is about. Best effort: a failed
  # lookup must never lose the comment.
  def post_context
    return if post_id.blank?

    @post_context ||= facebook? ? facebook_post : instagram_media
  rescue => e
    Rails.logger.error "VmMeta channel (#{channel.options[:callback_url_uuid]}) - post lookup failed: #{e.message}"
    nil
  end

  def facebook_post
    data = client.get(post_id, fields: 'message,permalink_url,created_time,full_picture')

    {
      text:      data['message'].to_s[0, POST_EXCERPT_LENGTH].presence,
      url:       data['permalink_url'],
      image_url: data['full_picture'],
      created:   data['created_time'],
    }.compact
  end

  def instagram_media
    data = client.get(post_id, fields: 'caption,permalink,media_type,timestamp,media_url,thumbnail_url')

    {
      text:      data['caption'].to_s[0, POST_EXCERPT_LENGTH].presence,
      url:       data['permalink'],
      image_url: data['thumbnail_url'].presence || data['media_url'],
      type:      data['media_type'],
      created:   data['timestamp'],
    }.compact
  end

  def client
    @client ||= VmMeta::Graph::Client.new(access_token: channel.options[:page_access_token])
  end

  # Internal note under the customer's comment: which post, in plain words.
  def add_post_context_note
    post = ticket.preferences.dig(:vm_meta_comment, :post)
    lines = ["Kommentar unter einem #{facebook? ? 'Facebook-Beitrag' : 'Instagram-Beitrag'}."]
    lines << "Beitrag: #{post[:text]}" if post&.dig(:text)
    lines << "Link: #{post[:url]}" if post&.dig(:url)
    lines << '(Der Beitrag konnte nicht geladen werden.)' if post.blank?
    lines << 'Eine Antwort hier erscheint öffentlich unter dem Kommentar.'

    Ticket::Article.create!(
      ticket_id:     ticket.id,
      content_type:  'text/plain',
      body:          lines.join("\n"),
      internal:      true,
      sender:        Ticket::Article::Sender.find_by(name: 'System'),
      type:          Ticket::Article::Type.find_by(name: 'note'),
      preferences:   { vm_meta_comment_context: true },
      updated_by_id: 1,
      created_by_id: 1,
    )
  rescue => e
    Rails.logger.error "VmMeta channel (#{channel.options[:callback_url_uuid]}) - post context note failed: #{e.message}"
  end
end
