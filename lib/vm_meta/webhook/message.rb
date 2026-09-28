# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Turns one Messenger/Instagram 'messaging' event into a customer, a ticket
# (one per open conversation per customer+channel, same rule as
# Whatsapp::Webhook::Message#find_ticket) and an article. Modeled directly on
# Whatsapp::Webhook::Message.
#
# NOTE on the customer id: a PSID (Messenger) / IGSID (Instagram) is only
# guaranteed unique *per page / per IG professional account*, not globally -
# two different Pages can hand out the same PSID to what are, in Meta's model,
# two unrelated people. Because of that:
#   - the Zammad login is page-scoped: "meta-messenger-<page_id>-<psid>" /
#     "meta-instagram-<ig_account_id>-<igsid>"
#   - the canonical "<page_or_account_id>:<sender_id>" pair is additionally
#     kept as vm_meta.contact_ref on both the ticket and the user's own
#     preferences, since another system (the CRM) shares this identifier
#     format and needs it verbatim, not reconstructed from the login string.
class VmMeta::Webhook::Message

  attr_reader :data, :page_id, :channel, :platform, :user, :ticket, :article

  def initialize(data:, page_id:, channel:, platform:)
    @data     = data
    @page_id  = page_id
    @channel  = channel
    @platform = platform
  end

  def process
    # Redelivery safety: Meta retries a webhook it didn't get a fast 200 for.
    return if mid.present? && Ticket::Article.exists?(message_id: mid)

    @user = create_or_update_user
    UserInfo.current_user_id = user.id

    @ticket  = create_or_update_ticket
    @article = create_article

    ticket
  end

  private

  def messenger?
    platform == 'messenger'
  end

  def message
    data[:message]
  end

  def mid
    message[:mid]
  end

  def text
    message[:text]
  end

  def attachments
    Array(message[:attachments])
  end

  def sender_id
    data.dig(:sender, :id).to_s
  end

  def timestamp
    data[:timestamp]
  end

  def contact_ref
    "#{page_id}:#{sender_id}"
  end

  def login
    prefix = messenger? ? 'meta-messenger' : 'meta-instagram'

    "#{prefix}-#{page_id}-#{sender_id}"
  end

  def create_or_update_user
    existing = User.find_by(login: login)
    return update_user(existing) if existing

    create_user
  end

  def create_user
    firstname, lastname = User.name_guess(profile_name)
    firstname = firstname.presence || profile_name
    lastname  = lastname.presence || ''

    User.create!(
      login:       login,
      firstname:   firstname,
      lastname:    lastname,
      active:      true,
      role_ids:    Role.signup_role_ids,
      preferences: { vm_meta: { contact_ref: } },
    )
  end

  def update_user(existing)
    preferences = existing.preferences
    preferences[:vm_meta] ||= {}
    return existing if preferences[:vm_meta][:contact_ref] == contact_ref

    preferences[:vm_meta][:contact_ref] = contact_ref
    existing.update!(preferences:)
    existing
  end

  def profile_name
    @profile_name ||= fetch_profile_name.presence || default_profile_name
  end

  def fetch_profile_name
    VmMeta::Graph::Profile.new(access_token: channel.options[:page_access_token], platform:).name(sender_id)
  rescue => e
    Rails.logger.error "VmMeta channel (#{channel.options[:callback_url_uuid]}) - profile lookup failed: #{e.message}"
    nil
  end

  def default_profile_name
    messenger? ? 'Facebook-Kontakt' : 'Instagram-Kontakt'
  end

  def user_display_name
    name = "#{user.firstname} #{user.lastname}".strip
    name.presence || profile_name
  end

  def create_or_update_ticket
    ticket = find_ticket
    return update_ticket(ticket) if ticket.present?

    create_ticket
  end

  def find_ticket
    state_ids        = Ticket::State.by_category_ids(:resolved)
    possible_tickets = Ticket.where(customer_id: user.id).where.not(state_id: state_ids).reorder(:updated_at)

    possible_tickets.find_each.find { |possible_ticket| possible_ticket.preferences[:channel_id] == channel.id }
  end

  def create_ticket
    Ticket.create!(
      group_id:    channel.group_id,
      title:       ticket_title,
      state_id:    Ticket::State.find_by(default_create: true).id,
      priority_id: Ticket::Priority.find_by(default_create: true).id,
      customer_id: user.id,
      preferences: {
        channel_id:   channel.id,
        channel_area: channel.area,
        vm_meta:      ticket_preferences,
      },
    )
  end

  def ticket_title
    messenger? ? "Facebook-Nachricht von #{user_display_name}" : "Instagram-Nachricht von #{user_display_name}"
  end

  def update_ticket(ticket)
    new_state_id = ticket.state_id == default_create_ticket_state.id ? ticket.state_id : default_follow_up_ticket_state.id

    preferences = ticket.preferences
    preferences[:vm_meta] ||= {}
    preferences[:vm_meta][:timestamp_incoming] = timestamp
    preferences[:vm_meta][:human_agent_tag]    = channel.options[:human_agent_tag] ? true : false

    ticket.update!(preferences:, state_id: new_state_id)

    ticket
  end

  def ticket_preferences
    {
      platform:,
      sender_id:,
      page_id:,
      contact_ref:,
      timestamp_incoming: timestamp,
      human_agent_tag:    channel.options[:human_agent_tag] ? true : false,
    }
  end

  def default_create_ticket_state
    Ticket::State.find_by(default_create: true)
  end

  def default_follow_up_ticket_state
    Ticket::State.find_by(default_follow_up: true)
  end

  def create_article
    article = Ticket::Article.create!(
      ticket_id:    ticket.id,
      type_id:      Ticket::Article::Type.lookup(name: article_type_name).id,
      sender_id:    Ticket::Article::Sender.lookup(name: 'Customer').id,
      from:         user_display_name,
      to:           channel.options[:name].to_s,
      message_id:   mid,
      internal:     false,
      body:         text.presence || '',
      content_type: 'text/plain',
    )

    create_attachments(article:) if attachments.present?

    article
  end

  def article_type_name
    messenger? ? 'messenger message' : 'instagram message'
  end

  def create_attachments(article:)
    attachments.each do |attachment|
      download_and_store(article:, attachment:)
    end
  end

  def download_and_store(article:, attachment:)
    url = attachment.dig(:payload, :url)
    return if url.blank?

    data, filename, mime_type = VmMeta::Incoming::Media.new.download(url:, attachment_type: attachment[:type])

    Store.create!(
      object:      'Ticket::Article',
      o_id:        article.id,
      data:,
      filename:,
      preferences: { 'Mime-Type' => mime_type },
    )
  rescue => e
    Rails.logger.error "VmMeta channel (#{channel.options[:callback_url_uuid]}) - attachment download failed: #{e.message}"
    note_attachment_error(article)
  end

  def note_attachment_error(article)
    preferences = article.preferences
    return if preferences[:vm_meta_media_error]

    preferences[:vm_meta_media_error] = true
    article.update!(preferences:)
  end
end
