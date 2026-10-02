# Daily performance report for one ticketing instance.
#
# Collects ticket stats for a given calendar date (default: yesterday in the
# instance's time zone), builds an HTML summary and sends it via the instance's
# own email channel. No Elasticsearch required; all queries are plain SQL.
#
# Configuration (environment variables, all optional):
#
#   VM_DAILY_REPORT_ENABLED     Set to "true" to enable sending. Default: false
#                               (build and log the report, but do not deliver).
#   VM_DAILY_REPORT_RECIPIENTS  Comma-separated email addresses. Required when
#                               enabled. Example: info@virtual-marketer.de,ceo@client.de
#   VM_DAILY_REPORT_GROUP       Zammad group name whose email channel is used as
#                               the sender. Default: first group with an active
#                               email channel.
#   VM_DAILY_REPORT_FROM_NAME   Display name for the From header.
#                               Default: "Virtual Marketer AI"
#
# Run manually:
#   bundle exec rake vm:daily_report               # yesterday, respects ENABLED flag
#   bundle exec rake vm:daily_report DATE=2026-09-29 DRY_RUN=1  # print HTML, no send
#
# This model is intentionally client-agnostic: it reads only from the Zammad DB
# and uses only tags / ticket counts, no customer PII. Safe to reuse as-is for
# any Virtual Marketer ticketing customer.

class VmDailyReport
  # Tags the pipeline sets — tracked in the report regardless of category.
  PIPELINE_TAGS = %w[
    ai_classified
    automatisierte_benachrichtigung
    ai_newsletter_detected
    ai_creditreform_detected
    voicemail
    fax
  ].freeze

  # Category tags the classifier assigns.
  CATEGORY_TAGS = %w[
    bestellung
    lieferung
    storno
    reklamation
    retoure
    technik
    vertrieb
    buchhaltung
    zahlung
    allgemeine_fragen
    grosshandel
  ].freeze

  CATEGORY_LABELS = {
    'bestellung'           => 'Bestellung',
    'lieferung'            => 'Lieferung',
    'storno'               => 'Storno',
    'reklamation'          => 'Reklamation',
    'retoure'              => 'Retoure',
    'technik'              => 'Technik',
    'vertrieb'             => 'Vertrieb',
    'buchhaltung'          => 'Buchhaltung',
    'zahlung'              => 'Zahlung',
    'allgemeine_fragen'    => 'Allg. Fragen',
    'grosshandel'          => 'Grosshandel',
    'automatisierte_benachrichtigung' => 'Benachrichtigungen',
    'ai_newsletter_detected'          => 'Newsletter',
    'ai_creditreform_detected'        => 'Creditreform',
  }.freeze

  SYSTEM_ACCOUNT_LOGINS = %w[info@virtual-marketer.de ai@the-platform-group.com].freeze

  attr_reader :date, :recipients

  def initialize(date: Date.yesterday, recipients: nil)
    @date       = date
    @recipients = Array(recipients || ENV.fetch('VM_DAILY_REPORT_RECIPIENTS', 'info@virtual-marketer.de').split(',').map(&:strip))
  end

  def stats
    @stats ||= build_stats
  end

  def html
    @html ||= build_html
  end

  # Creates a closed Zammad ticket and sends the report as an outbound email
  # via the instance's own mail channel. Triggers and agent notifications are
  # suppressed so the report ticket does not appear in any queue.
  def deliver!
    channel_email = sending_channel_email
    group         = sending_group

    Transaction.execute(disable: %w[Transaction::Trigger Transaction::Notification Transaction::TimeBasedTrigger]) do
      ticket = Ticket.create!(
        title:          "Tagesbericht #{date.strftime('%d.%m.%Y')} | Virtual Marketer AI",
        group_id:       group.id,
        state_id:       Ticket::State.find_by(name: 'closed').id,
        priority_id:    Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first.id,
        customer_id:    (User.find_by(email: recipients.first) || User.find(1)).id,
        created_by_id:  1,
        updated_by_id:  1,
      )

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       Ticket::Article::Type.find_by(name: 'email').id,
        sender_id:     Ticket::Article::Sender.find_by(name: 'Agent').id,
        from:          "#{from_name} <#{channel_email}>",
        to:            recipients.join(', '),
        subject:       "Tagesbericht #{date.strftime('%d.%m.%Y')}: Virtual Marketer AI",
        body:          html,
        content_type:  'text/html',
        internal:      false,
        created_by_id: 1,
        updated_by_id: 1,
      )
    end
  end

  private

  def build_stats
    range  = day_range
    merged_state_ids = Ticket::State.by_category_ids(:merged)
    open_state_ids   = Ticket::State.by_category_ids(:open)
    closed_state_ids = Ticket::State.by_category_ids(:closed)

    # Tickets created yesterday, excluding duplicates (merged state).
    created = Ticket.where(created_at: range).where.not(state_id: merged_state_ids)
    created_ids = created.pluck(:id)

    # Tickets closed yesterday.
    closed_yesterday = Ticket.where(close_at: range).where.not(state_id: merged_state_ids)

    # Current open count.
    open_now = Ticket.where(state_id: open_state_ids).count

    {
      date:              date,
      created_total:     created_ids.size,
      tag_counts:        tag_counts_for(created_ids),
      closed_yesterday:  closed_yesterday.count,
      open_now:          open_now,
      agents:            agent_stats(closed_yesterday, open_state_ids),
      ai:                ai_stats,
      first_response_measured: first_response_measured?,
      avg_first_response_minutes: avg_first_response_minutes_since_mailbox,
    }
  end

  def day_range
    tz   = ActiveSupport::TimeZone['Europe/Berlin']
    from = tz.local(date.year, date.month, date.day)
    from..from.end_of_day
  end

  # { tag_name => count } for the given ticket ids.
  def tag_counts_for(ticket_ids)
    return {} if ticket_ids.empty?

    tracked = PIPELINE_TAGS + CATEGORY_TAGS
    ticket_obj = Tag::Object.find_by(name: 'Ticket')
    return {} unless ticket_obj

    items = Tag::Item.where(name: tracked).index_by(&:name)
    return {} if items.empty?

    counts = Tag
      .where(tag_object_id: ticket_obj.id, o_id: ticket_ids, tag_item_id: items.values.map(&:id))
      .group(:tag_item_id)
      .count

    # { tag_item_id => tag_name } for the reverse lookup
    id_to_name = items.to_h { |name, item| [item.id, name] }
    counts.each_with_object({}) do |(tag_item_id, count), acc|
      name = id_to_name[tag_item_id]
      acc[name] = count if name
    end
  end

  # Gaps between two changes of one agent longer than this count as a break.
  ACTIVE_GAP_MINUTES = 30

  # One row per agent who did anything yesterday or owns tickets. An agent with
  # no solved and no owned tickets used to be dropped, which hid people who had
  # worked in other agents' tickets all day (replying, noting, assigning).
  def agent_stats(closed_yesterday, open_state_ids)
    agents = User.with_permissions('ticket.agent').where(active: true).where.not(id: 1).to_a.uniq

    closed_by = closed_yesterday.where.not(owner_id: 1).group(:owner_id).count
    open_by   = Ticket.where(state_id: open_state_ids).where.not(owner_id: 1).group(:owner_id).count
    history   = history_by_user(agents.map(&:id))
    replies   = reply_minutes_by_user(agents.map(&:id))

    agents
      .sort_by { |u| [SYSTEM_ACCOUNT_LOGINS.include?(u.login) ? 1 : 0, u.fullname.downcase] }
      .filter_map do |u|
        system = SYSTEM_ACCOUNT_LOGINS.include?(u.login)
        solved = closed_by[u.id] || 0
        open   = open_by[u.id]   || 0
        act    = history[u.id]
        next if solved.zero? && open.zero? && act.nil? && !system

        active_min = act ? act[:active_minutes] : 0
        touched    = act ? act[:tickets] : 0
        rep        = replies[u.id] || []

        {
          name:           u.fullname,
          system:         system,
          solved:         solved,
          open:           open,
          first_at:       act&.dig(:first_at),
          last_at:        act&.dig(:last_at),
          active_minutes: active_min,
          tickets:        touched,
          minutes_per_ticket: touched.positive? ? (active_min.to_f / touched).round : nil,
          replies:        rep.size,
          median_reply_minutes: median(rep),
        }
      end
  end

  # { user_id => { first_at:, last_at:, active_minutes:, tickets: } } from the
  # change history of the report day. History records every change an agent
  # makes (state, owner, articles, tags), so it is the nearest thing to "was
  # working in the system"; merely viewing a ticket leaves no trace.
  def history_by_user(user_ids)
    ticket_obj  = History::Object.find_by(name: 'Ticket')
    article_obj = History::Object.find_by(name: 'Ticket::Article')
    rows = History
      .where(created_at: day_range, created_by_id: user_ids)
      .pluck(:created_by_id, :created_at, :history_object_id, :o_id, :related_o_id)

    rows.group_by(&:first).transform_values do |list|
      times   = list.map { |r| r[1] }.sort
      tickets = list.filter_map do |_, _, obj, o_id, related|
        if obj == ticket_obj&.id then o_id
        elsif obj == article_obj&.id then related
        end
      end.uniq

      active = times.each_cons(2).sum do |a, b|
        gap = (b - a) / 60.0
        gap <= ACTIVE_GAP_MINUTES ? gap : 0
      end

      { first_at: times.first, last_at: times.last, active_minutes: active.round, tickets: tickets.size }
    end
  end

  # { user_id => [minutes, ...] }: for every public email the agent sent
  # yesterday, the time since the customer's last message in that ticket.
  # Wall-clock time (nights and weekends included), so a reply to a mail that
  # arrived the evening before reads long. Replies with no earlier customer
  # message (outbound first contact) are skipped.
  def reply_minutes_by_user(user_ids)
    agent_sender    = Ticket::Article::Sender.find_by(name: 'Agent')
    customer_sender = Ticket::Article::Sender.find_by(name: 'Customer')
    email_type      = Ticket::Article::Type.find_by(name: 'email')
    return {} unless agent_sender && customer_sender && email_type

    sent = Ticket::Article.where(
      created_at: day_range, internal: false, sender_id: agent_sender.id,
      type_id: email_type.id, created_by_id: user_ids
    ).pluck(:ticket_id, :created_by_id, :created_at)

    sent.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(ticket_id, user_id, at), acc|
      prev = Ticket::Article
        .where(ticket_id: ticket_id, sender_id: customer_sender.id)
        .where(created_at: ...at).maximum(:created_at)
      next unless prev

      acc[user_id] << ((at - prev) / 60.0).round
    end
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid    = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
  end

  # What the pipeline prepared yesterday, read from its own internal notes.
  # Virtual Marketer only prepares; nobody here is answered by it. "Real"
  # tickets are the ones that got a full classification (pre-handled spam,
  # newsletters and automated mails carry a different note and need no reply).
  def ai_stats
    base  = Ticket::Article.where(created_at: day_range, internal: true)
    notes = base.where("body LIKE '%Klassifikation</h3>%'").pluck(:ticket_id, :body)
    pre   = base.where("body LIKE '%Vorab-Erkennung</h3>%'").pluck(:ticket_id).uniq.size

    # A ticket can carry two notes if the pipeline ran twice; count it once.
    by_ticket = notes.each_with_object({}) { |(tid, body), acc| acc[tid] = body }
    bodies    = by_ticket.values

    {
      tickets_with_note:  by_ticket.size + pre,
      needs_reply:        by_ticket.size,
      pre_handled:        pre,
      xentral_lookups:    bodies.sum { |b| b.scan('<b>Xentral (').size },
      customers_found:    bodies.count { |b| b.include?('module=adresse') },
      orders_found:       bodies.count { |b| b.include?('module=auftrag') },
      invoices_found:     bodies.count { |b| b.include?('module=rechnung') },
      invoice_pdfs:       bodies.count { |b| b.include?('Rechnung als PDF') },
      drafts:             bodies.count { |b| b.include?('Antwortvorschlag') },
      shop_links:         bodies.count { |b| b.include?('Shop (Produktseiten)') },
    }
  end

  # First-response time is only meaningful since the mailbox was connected
  # (tickets before that have no first_response_at). We average over the last
  # 30 days so a single slow day does not distort the number.
  def first_response_measured?
    Ticket.where(first_response_at: 30.days.ago..).exists?
  end

  def avg_first_response_minutes_since_mailbox
    rows = Ticket
      .where(first_response_at: 30.days.ago..)
      .pluck(:created_at, :first_response_at)
    return nil if rows.empty?

    (rows.sum { |c, r| (r - c) / 60.0 } / rows.size).round
  end

  def sending_group
    name = ENV.fetch('VM_DAILY_REPORT_GROUP', nil)
    if name.present?
      Group.find_by!(name: name)
    else
      # Use the first group that has an active email channel associated.
      Group.joins(:email_address).first ||
        Group.find_by(name: 'Kundenservice') ||
        Group.first
    end
  end

  def sending_channel_email
    ch = Channel.where(area: 'Email::Account', active: true).first
    ch&.options&.dig('inbound', 'options', 'user') ||
      ch&.options&.dig('inbound', 'options', 'email') ||
      sending_group.email_address&.email ||
      'noreply@virtual-marketer.de'
  end

  def from_name
    ENV.fetch('VM_DAILY_REPORT_FROM_NAME', 'Virtual Marketer AI')
  end


  # -------------------------------------------------------------------------
  # HTML rendering
  #
  # Mail clients ignore <style> blocks and flexbox (Outlook renders with the
  # Word engine), so everything is table layout with inline styles. No
  # external fonts or images.
  # -------------------------------------------------------------------------

  FONT   = "font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;".freeze
  NAVY   = '#1a2a4a'.freeze
  BLUE   = '#3a7bd5'.freeze
  INK    = '#222b3a'.freeze
  MUTED  = '#6b7686'.freeze
  LINE   = '#e6e9ef'.freeze
  CARD   = '#f4f6fa'.freeze
  GREEN  = '#2e8b57'.freeze

  WEEKDAYS = %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag].freeze
  MONTHS   = %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember].freeze

  def build_html
    s   = stats
    tag = s[:tag_counts]
    ai  = s[:ai]

    classified = tag['ai_classified'] || 0
    prehandled = %w[automatisierte_benachrichtigung ai_newsletter_detected ai_creditreform_detected].sum { |t| tag[t] || 0 }
    total      = s[:created_total]

    category_rows = CATEGORY_TAGS.filter_map do |t|
      n = tag[t] || 0
      n.positive? ? [CATEGORY_LABELS.fetch(t, t), n] : nil
    end.sort_by { |_, n| -n }
    prehandled_rows = %w[automatisierte_benachrichtigung ai_newsletter_detected ai_creditreform_detected].filter_map do |t|
      n = tag[t] || 0
      n.positive? ? [CATEGORY_LABELS.fetch(t, t), n] : nil
    end

    cards = [
      kpi_card(total, 'Tickets eingegangen', nil),
      kpi_card(s[:closed_yesterday], 'erledigt', nil),
      kpi_card(s[:open_now], 'offen gesamt', nil),
      (s[:first_response_measured] && s[:avg_first_response_minutes] ? kpi_card(duration(s[:avg_first_response_minutes]), 'Erstantwort', '30 Tage Ø') : nil),
    ].compact
    extra = []
    extra << [tag['voicemail'], 'Voicemails'] if (tag['voicemail'] || 0).positive?
    extra << [tag['fax'], 'Faxe']             if (tag['fax'] || 0).positive?

    <<~HTML
      <!DOCTYPE html>
      <html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tagesbericht #{h date.strftime('%d.%m.%Y')}</title></head>
      <body style="margin:0;padding:0;background:#eef1f6;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#eef1f6;"><tr><td align="center" style="padding:24px 12px;">
      <table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:640px;background:#ffffff;border-radius:8px;overflow:hidden;#{FONT}color:#{INK};">

        <tr><td style="background:#{NAVY};padding:26px 32px 22px;">
          <div style="#{FONT}font-size:12px;letter-spacing:1.2px;text-transform:uppercase;color:#9fb3d1;">Tagesbericht</div>
          <div style="#{FONT}font-size:24px;font-weight:700;color:#ffffff;margin-top:6px;">#{h long_date(date)}</div>
          <div style="#{FONT}font-size:13px;color:#9fb3d1;margin-top:6px;">#{h(Setting.get('fqdn') || 'Ticketing')} &middot; Virtual Marketer</div>
        </td></tr>

        <tr><td style="padding:24px 32px 8px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>#{cards.join}</tr></table>
          #{extra.any? ? "<div style=\"#{FONT}font-size:12px;color:#{MUTED};margin-top:12px;\">Darunter: " + extra.map { |n, l| "#{n} #{l}" }.join(', ') + '</div>' : ''}
        </td></tr>

        #{category_rows.any? ? category_section(category_rows, prehandled_rows, classified, prehandled, total) : ''}
        #{ai_section(ai, total)}
        #{s[:agents].any? ? agent_section(s[:agents]) : ''}

        <tr><td style="padding:20px 32px 28px;#{FONT}font-size:11px;line-height:1.6;color:#{MUTED};">
          Erstellt automatisch am #{Time.zone.now.in_time_zone('Europe/Berlin').strftime('%d.%m.%Y um %H:%M')} Uhr.
          Erstantwort: Durchschnitt der letzten 30 Tage, gemessen ab Anbindung des Postfachs.
          Aktive Zeit: Zeitspanne zwischen Änderungen im System, Pausen über #{ACTIVE_GAP_MINUTES} Minuten zählen nicht mit; reines Ansehen eines Tickets wird nicht erfasst.
          Antwortzeit: Median von der letzten Kundennachricht bis zur Antwort, rund um die Uhr gerechnet.
        </td></tr>

      </table>
      </td></tr></table>
      </body></html>
    HTML
  end

  def kpi_card(value, label, sub)
    <<~TD
      <td width="25%" valign="top" style="padding:0 4px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#{CARD};border-radius:6px;"><tr><td align="center" style="padding:14px 6px;">
          <div style="#{FONT}font-size:26px;font-weight:700;color:#{NAVY};line-height:1.1;">#{h value}</div>
          <div style="#{FONT}font-size:11px;color:#{MUTED};margin-top:4px;">#{h label}</div>
          #{sub ? "<div style=\"#{FONT}font-size:10px;color:#9aa4b2;margin-top:2px;\">#{h sub}</div>" : ''}
        </td></tr></table>
      </td>
    TD
  end

  def section_open(title, lead = nil)
    <<~HTML
      <tr><td style="padding:22px 32px 4px;">
        <div style="#{FONT}font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:#{BLUE};padding-bottom:6px;border-bottom:2px solid #{LINE};">#{h title}</div>
        #{lead ? "<div style=\"#{FONT}font-size:12px;line-height:1.5;color:#{MUTED};margin-top:8px;\">#{h lead}</div>" : ''}
    HTML
  end

  def category_section(category_rows, prehandled_rows, classified, prehandled, total)
    max  = [category_rows.map(&:last).max || 1, 1].max
    rows = category_rows.map do |label, n|
      pct = [(n * 100.0 / max).round, 3].max
      <<~TR
        <tr>
          <td width="110" style="padding:6px 0;#{FONT}font-size:13px;color:#{INK};">#{h label}</td>
          <td style="padding:6px 8px;"><table role="presentation" width="#{pct}%" cellpadding="0" cellspacing="0" border="0"><tr><td height="10" style="background:#{BLUE};border-radius:3px;font-size:1px;line-height:10px;">&nbsp;</td></tr></table></td>
          <td width="36" align="right" style="padding:6px 0;#{FONT}font-size:13px;font-weight:700;color:#{NAVY};">#{n}</td>
        </tr>
      TR
    end.join

    pre = prehandled_rows.map do |label, n|
      "<tr><td style=\"padding:3px 0;#{FONT}font-size:12px;color:#{MUTED};\">#{h label}</td><td></td><td align=\"right\" style=\"padding:3px 0;#{FONT}font-size:12px;color:#{MUTED};\">#{n}</td></tr>"
    end.join

    pct = total.positive? ? (classified * 100 / total) : 0
    section_open('Nach Bereich') + <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:6px;">#{rows}</table>
        #{prehandled_rows.any? ? "<div style=\"#{FONT}font-size:11px;color:#{MUTED};margin-top:10px;\">Vorab erkannt, kein Handlungsbedarf</div><table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\">#{pre}</table>" : ''}
        <div style="#{FONT}font-size:12px;color:#{MUTED};margin-top:10px;">#{classified} von #{total} Tickets (#{pct} %) wurden von Virtual Marketer klassifiziert, davon #{prehandled} vorab als nicht handlungsrelevant erkannt.</div>
      </td></tr>
    HTML
  end

  def ai_section(ai, total)
    return '' if ai.nil? || ai[:tickets_with_note].zero?

    needs  = ai[:needs_reply]
    drafts = ai[:drafts]
    pct    = needs.positive? ? (drafts * 100 / needs) : 0

    cards = [
      kpi_card(needs, 'Tickets mit Anliegen', nil),
      kpi_card(drafts, 'Antwortentwürfe', "#{pct} % davon"),
      kpi_card(ai[:xentral_lookups], 'Xentral Abfragen', nil),
      kpi_card(ai[:customers_found], 'Kunden erkannt', nil),
    ].join

    cards2 = [
      kpi_card(ai[:orders_found], 'Aufträge gefunden', nil),
      kpi_card(ai[:invoices_found], 'Rechnungen gefunden', nil),
      kpi_card(ai[:invoice_pdfs], 'Rechnungs PDF angehängt', nil),
      kpi_card(ai[:shop_links], 'mit Shop Links', nil),
    ].join

    section_open('Vorbereitet von Virtual Marketer', 'Virtual Marketer prüft jedes eingehende Ticket und legt die Ergebnisse als interne Notiz ab. Es wird nichts automatisch an Kunden gesendet, die Antwort schreibt und sendet weiterhin das Team.') + <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:12px;"><tr>#{cards}</tr></table>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;"><tr>#{cards2}</tr></table>
        <div style="#{FONT}font-size:12px;color:#{MUTED};margin-top:10px;">#{ai[:pre_handled]} weitere Tickets (Newsletter, Benachrichtigungen, Creditreform) wurden vorab erkannt und brauchen keine Antwort.</div>
      </td></tr>
    HTML
  end

  def agent_section(agents)
    th = "padding:6px 4px;#{FONT}font-size:10px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;color:#{MUTED};border-bottom:1px solid #{LINE};"
    rows = agents.map do |a|
      color = a[:system] ? '#9aa4b2' : INK
      td    = "padding:8px 4px;#{FONT}font-size:12px;color:#{color};border-bottom:1px solid #{LINE};"
      window = a[:first_at] ? "#{berlin(a[:first_at])} bis #{berlin(a[:last_at])}" : 'keine Aktivität'
      active = a[:first_at] ? duration(a[:active_minutes]) : ''
      per    = a[:minutes_per_ticket] ? duration(a[:minutes_per_ticket]) : ''
      reply  = a[:median_reply_minutes] ? "#{duration(a[:median_reply_minutes])} (#{a[:replies]})" : ''
      if a[:system]
        window = 'Automatik'
        active = per = reply = ''
      end
      <<~TR
        <tr>
          <td style="#{td}font-weight:700;">#{h a[:name]}</td>
          <td style="#{td}">#{h window}</td>
          <td style="#{td}" align="right">#{h active}</td>
          <td style="#{td}" align="right">#{a[:first_at] && !a[:system] ? a[:tickets] : ''}</td>
          <td style="#{td}" align="right">#{h per}</td>
          <td style="#{td}" align="right">#{h reply}</td>
          <td style="#{td}color:#{a[:system] ? color : GREEN};font-weight:700;" align="right">#{a[:solved]}</td>
          <td style="#{td}" align="right">#{a[:open]}</td>
        </tr>
      TR
    end.join

    section_open('Team gestern') + <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:6px;border-collapse:collapse;">
          <tr>
            <td style="#{th}">Person</td>
            <td style="#{th}">Aktiv</td>
            <td style="#{th}" align="right">Zeit</td>
            <td style="#{th}" align="right">Tickets</td>
            <td style="#{th}" align="right">Ø je Ticket</td>
            <td style="#{th}" align="right">Antwortzeit</td>
            <td style="#{th}" align="right">Erledigt</td>
            <td style="#{th}" align="right">Offen</td>
          </tr>
          #{rows}
        </table>
      </td></tr>
    HTML
  end

  def long_date(d)
    "#{WEEKDAYS[d.wday]}, #{d.day}. #{MONTHS[d.month - 1]} #{d.year}"
  end

  def berlin(time)
    time.in_time_zone('Europe/Berlin').strftime('%H:%M')
  end

  def duration(minutes)
    return '' if minutes.nil?

    return 'unter 1 min' if minutes.zero?

    hours, mins = minutes.divmod(60)
    hours.positive? ? "#{hours} h #{mins} min" : "#{mins} min"
  end

  def h(str)
    CGI.escapeHTML(str.to_s)
  end
end
