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
        customer_id:    User.find_by(email: recipients.first) || User.first,
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

  def agent_stats(closed_yesterday, open_state_ids)
    agents = User
      .with_permissions('ticket.agent')
      .where(active: true)
      .where.not(id: 1)
      .distinct

    closed_by = closed_yesterday.where.not(owner_id: 1).group(:owner_id).count
    open_by   = Ticket.where(state_id: open_state_ids).where.not(owner_id: 1).group(:owner_id).count

    agents
      .sort_by { |u| [SYSTEM_ACCOUNT_LOGINS.include?(u.login) ? 1 : 0, u.fullname.downcase] }
      .filter_map do |u|
        solved = closed_by[u.id] || 0
        open   = open_by[u.id]   || 0
        next if solved == 0 && open == 0 && !SYSTEM_ACCOUNT_LOGINS.include?(u.login)

        { name: u.fullname, system: SYSTEM_ACCOUNT_LOGINS.include?(u.login), solved: solved, open: open }
      end
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
  # -------------------------------------------------------------------------

  def build_html
    s = stats
    tag = s[:tag_counts]

    classified   = tag['ai_classified']                  || 0
    prehandled   = (tag['automatisierte_benachrichtigung'] || 0) +
                   (tag['ai_newsletter_detected']          || 0) +
                   (tag['ai_creditreform_detected']        || 0)
    voicemails   = tag['voicemail'] || 0
    faxes        = tag['fax']       || 0
    total        = s[:created_total]
    pct          = total.positive? ? (classified * 100 / total) : 0

    category_rows = CATEGORY_TAGS.filter_map do |t|
      n = tag[t] || 0
      n.positive? ? [CATEGORY_LABELS.fetch(t, t), n] : nil
    end.sort_by { |_, n| -n }

    prehandled_rows = %w[automatisierte_benachrichtigung ai_newsletter_detected ai_creditreform_detected].filter_map do |t|
      n = tag[t] || 0
      n.positive? ? [CATEGORY_LABELS.fetch(t, t), n] : nil
    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="de">
      <head><meta charset="utf-8">
      <style>
        body { font-family: Arial, Helvetica, sans-serif; font-size: 14px; color: #222; margin: 0; padding: 0; background: #f5f5f5; }
        .wrap { max-width: 620px; margin: 24px auto; background: #fff; border-radius: 6px; overflow: hidden; }
        .header { background: #1a2a4a; color: #fff; padding: 20px 28px 16px; }
        .header h1 { margin: 0; font-size: 18px; font-weight: bold; }
        .header p  { margin: 4px 0 0; font-size: 13px; color: #a0b4cc; }
        .section   { padding: 20px 28px; border-bottom: 1px solid #eee; }
        .section h2 { margin: 0 0 12px; font-size: 14px; text-transform: uppercase; letter-spacing: .5px; color: #555; }
        .kpi-row { display: flex; gap: 16px; flex-wrap: wrap; }
        .kpi     { flex: 1 1 120px; background: #f8f9fc; border-radius: 5px; padding: 12px 16px; text-align: center; }
        .kpi .val { font-size: 26px; font-weight: bold; color: #1a2a4a; }
        .kpi .lbl { font-size: 11px; color: #777; margin-top: 2px; }
        .kpi .sub { font-size: 10px; color: #aaa; margin-top: 3px; }
        table  { width: 100%; border-collapse: collapse; font-size: 13px; }
        th     { text-align: left; color: #777; font-weight: normal; font-size: 12px; padding: 4px 8px 4px 0; border-bottom: 1px solid #eee; }
        td     { padding: 5px 8px 5px 0; border-bottom: 1px solid #f3f3f3; }
        td.n   { text-align: right; padding-right: 0; font-variant-numeric: tabular-nums; }
        .bar   { display: inline-block; height: 8px; background: #3a7bd5; border-radius: 3px; vertical-align: middle; }
        .footer { padding: 16px 28px; font-size: 11px; color: #999; }
      </style>
      </head>
      <body>
      <div class="wrap">
        <div class="header">
          <h1>Tagesbericht: #{h date.strftime('%d.%m.%Y')}</h1>
          <p>Virtual Marketer AI | #{h Setting.get('fqdn') || 'Ticketing'}</p>
        </div>

        <div class="section">
          <h2>Ticket-Eingang gestern</h2>
          <div class="kpi-row">
            <div class="kpi"><div class="val">#{total}</div><div class="lbl">Tickets eingegangen</div></div>
            <div class="kpi"><div class="val">#{classified}</div><div class="lbl">KI-klassifiziert (#{pct}%)</div><div class="sub">#{prehandled} deterministisch &middot; #{classified - prehandled} KI</div></div>
            #{voicemails.positive? ? "<div class=\"kpi\"><div class=\"val\">#{voicemails}</div><div class=\"lbl\">Voicemails</div></div>" : ''}
            #{faxes.positive? ? "<div class=\"kpi\"><div class=\"val\">#{faxes}</div><div class=\"lbl\">Faxe</div></div>" : ''}
          </div>
        </div>

        #{category_rows.any? ? category_section(category_rows, prehandled_rows, total) : ''}

        <div class="section">
          <h2>Ticket-Bestand</h2>
          <div class="kpi-row">
            <div class="kpi"><div class="val">#{s[:open_now]}</div><div class="lbl">offen (gesamt)</div></div>
            <div class="kpi"><div class="val">#{s[:closed_yesterday]}</div><div class="lbl">gestern erledigt</div></div>
            #{s[:first_response_measured] && s[:avg_first_response_minutes] ? first_response_kpi(s[:avg_first_response_minutes]) : ''}
          </div>
        </div>

        #{s[:agents].any? ? agent_section(s[:agents]) : ''}

        <div class="footer">
          Erstellt automatisch am #{Time.zone.now.strftime('%d.%m.%Y %H:%M')} Uhr.
          Erstantwortzeit: Durchschnitt der letzten 30 Tage (ab Mailbox-Anbindung).
        </div>
      </div>
      </body></html>
    HTML
  end

  def category_section(category_rows, prehandled_rows, total)
    max = [category_rows.map(&:last).max || 1, 1].max
    rows_html = category_rows.map do |label, n|
      bar_w = (n * 80 / max).round
      <<~TR
        <tr>
          <td>#{h label}</td>
          <td><span class="bar" style="width:#{bar_w}px"></span></td>
          <td class="n">#{n}</td>
        </tr>
      TR
    end.join

    prehandled_html = prehandled_rows.map do |label, n|
      "<tr><td>#{h label}</td><td></td><td class=\"n\">#{n}</td></tr>"
    end.join

    <<~HTML
      <div class="section">
        <h2>Nach Bereich</h2>
        <table>
          <tr><th>Kategorie</th><th></th><th style="text-align:right">Tickets</th></tr>
          #{rows_html}
          #{prehandled_rows.any? ? "<tr><td colspan='3' style='padding-top:8px;color:#999;font-size:12px'>Vorab erkannt (kein Handlungsbedarf)</td></tr>#{prehandled_html}" : ''}
        </table>
      </div>
    HTML
  end

  def first_response_kpi(minutes)
    h, m = minutes.divmod(60)
    label = h.positive? ? "#{h}h #{m}min" : "#{m}min"
    "<div class=\"kpi\"><div class=\"val\">#{label}</div><div class=\"lbl\">Erstantwort (30-Tage-Ø)</div></div>"
  end

  def agent_section(agents)
    rows_html = agents.map do |a|
      dim = a[:system] ? ' style="color:#aaa;font-size:12px"' : ''
      "<tr#{dim}><td>#{h a[:name]}</td><td class=\"n\">#{a[:solved]}</td><td class=\"n\">#{a[:open]}</td></tr>"
    end.join

    <<~HTML
      <div class="section">
        <h2>Team (gestern)</h2>
        <table>
          <tr><th>Agent</th><th style="text-align:right">Erledigt</th><th style="text-align:right">Offen</th></tr>
          #{rows_html}
        </table>
      </div>
    HTML
  end

  def h(str)
    CGI.escapeHTML(str.to_s)
  end
end
