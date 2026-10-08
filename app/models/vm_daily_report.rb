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
    @recipients = Array(recipients || ENV.fetch('VM_DAILY_REPORT_RECIPIENTS', 'info@virtual-marketer.de').split(',')).map(&:strip).reject(&:blank?)
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
    # An empty list would still create a ticket (find_by(email: nil) matches any
    # user without an address) and mail nobody, silently.
    raise 'VmDailyReport: no recipients configured (VM_DAILY_REPORT_RECIPIENTS)' if recipients.empty?

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

      article = Ticket::Article.create!(
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

      # Ticket::Article sanitizes HTML bodies on create (HtmlSanitizer::Strict):
      # it drops every CSS property outside a small allowlist (font-size,
      # font-weight, letter-spacing, height, margin ...) and every remote image,
      # which is what flattened the first mail layouts in Gmail. This body is
      # generated by us from escaped values only, so the finished markup is
      # written back verbatim. update_columns skips the callback; the mail job
      # runs after commit and reads this value.
      article.update_columns(body: html) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def build_stats
    range  = day_range
    merged_state_ids = Ticket::State.by_category_ids(:merged)
    open_state_ids   = Ticket::State.by_category_ids(:open)
    closed_state_ids = Ticket::State.by_category_ids(:closed)

    # The report's own ticket is created closed, so without this every report
    # counted yesterday's report once as new and once as solved.
    own_reports = Ticket.where(created_by_id: 1).where('title LIKE ?', 'Tagesbericht %| Virtual Marketer AI')

    # Tickets created yesterday, excluding duplicates (merged state).
    created = Ticket.where(created_at: range).where.not(state_id: merged_state_ids).where.not(id: own_reports)
    created_ids = created.pluck(:id)

    # Tickets closed yesterday.
    closed_yesterday = Ticket.where(close_at: range).where.not(state_id: merged_state_ids).where.not(id: own_reports)

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

    closed_by = closed_by_user(agents.map(&:id))
    open_by   = Ticket.where(state_id: open_state_ids).where.not(owner_id: 1).group(:owner_id).count
    history   = history_by_user(agents.map(&:id))
    replies   = reply_minutes_by_user(agents.map(&:id))

    # Ranked by tickets solved, most first. The automation account takes its
    # place in that ranking like a person: what it closes (noise, phishing,
    # silent voicemails) is work nobody on the team had to do.
    agents
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
      .sort_by { |a| [-a[:solved], a[:system] ? 1 : 0, a[:name].downcase] }
  end

  # { user_id => tickets this person set to a closed state on the report day }.
  # Counted from the history, not from the owner: most tickets are closed by
  # whoever picks them up while the owner stays "nobody", so counting by owner
  # showed Nora at 2 for a week in which she closed 70.
  def closed_by_user(user_ids)
    ticket_obj = History::Object.find_by(name: 'Ticket')
    state_attr = History::Attribute.find_by(name: 'state')
    return {} unless ticket_obj && state_attr

    History
      .where(history_object_id: ticket_obj.id, history_attribute_id: state_attr.id,
             created_by_id: user_ids, created_at: day_range,
             value_to: Ticket::State.where(id: Ticket::State.by_category_ids(:closed)).pluck(:name))
      .group(:created_by_id)
      .distinct
      .count(:o_id)
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
    pre_ids = base.where("body LIKE '%Vorab-Erkennung</h3>%'").pluck(:ticket_id).uniq

    # A ticket can carry two notes if the pipeline ran twice; count it once.
    by_ticket = notes.each_with_object({}) { |(tid, body), acc| acc[tid] = body }
    bodies    = by_ticket.values

    {
      tickets_with_note:  (by_ticket.keys | pre_ids).size,
      needs_reply:        by_ticket.size,
      pre_handled:        (pre_ids - by_ticket.keys).size,
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
  # Word engine), so everything is table layout with inline styles, bgcolor
  # attributes next to every background, and pixel widths on bar cells (a
  # percentage-width table nested in a cell collapses in Gmail).
  #
  # Every sentence in the report comes from a fixed template filled with
  # numbers from the database. Nothing is estimated and nothing is written by
  # a language model, so the same data always yields the same report.
  #
  # Colours are the Virtual Marketer palette (virtual-marketer.css).
  # -------------------------------------------------------------------------

  FONT      = "font-family:Inter,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;".freeze
  RED       = '#94152b'.freeze
  RED_SOFT  = '#fbf2f3'.freeze
  BLUE      = '#66a3ce'.freeze
  BLUE_SOFT = '#eef5fa'.freeze
  INK       = '#1a202c'.freeze
  TEXT      = '#2d3748'.freeze
  MUTED     = '#4a5568'.freeze
  SOFT      = '#718096'.freeze
  LINE      = '#e2e8f0'.freeze
  CARD      = '#f7fafc'.freeze
  GREEN     = '#1a7a3c'.freeze
  PAGE      = '#edf2f7'.freeze
  # A phone leaves about 270 px for content (360 px screen, page and card
  # padding). Nothing in the layout may be wider than that, or Gmail on the
  # phone cuts the right side off: no fixed widths that add up past it, and
  # no row with more than three columns.
  BAR_MAX_PX = 240
  PAD_X      = 20

  WEEKDAYS = %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag].freeze
  MONTHS   = %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember].freeze

  # Tickets Virtual Marketer recognises up front as needing no answer.
  PREHANDLED = {
    'automatisierte_benachrichtigung' => ['Automatische Meldungen', 'Mails von Systemen, zum Beispiel Versand- oder Zahlungsmeldungen.'],
    'ai_newsletter_detected'          => ['Newsletter', 'Newsletter und Abmeldungen.'],
    'ai_creditreform_detected'        => ['Creditreform', 'Anfragen der Auskunftei Creditreform.'],
  }.freeze

  def build_html
    s     = stats
    tag   = s[:tag_counts]
    ai    = s[:ai]
    total = s[:created_total]

    pre_rows   = PREHANDLED.filter_map { |t, (label, note)| (tag[t] || 0).positive? ? [label, note, tag[t]] : nil }
    # A ticket can carry two pre-handling tags; never report more than all.
    prehandled = [pre_rows.sum { |_, _, n| n }, total].min
    lines      = summary_lines(s, ai, prehandled)

    <<~HTML
      <!DOCTYPE html>
      <html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>Tagesbericht #{h date.strftime('%d.%m.%Y')}</title></head>
      <body style="margin:0;padding:0;background:#{PAGE};" bgcolor="#{PAGE}">
      <div style="display:none;max-height:0;overflow:hidden;font-size:1px;line-height:1px;color:#{PAGE};">#{h lines.first}</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#{PAGE}" style="background:#{PAGE};"><tr><td align="center" style="padding:16px 8px;">
      <table role="presentation" align="center" width="640" cellpadding="0" cellspacing="0" border="0" bgcolor="#ffffff" style="width:100%;max-width:640px;margin:0 auto;background:#ffffff;#{FONT}color:#{TEXT};">

        #{header_row}
        #{overview_row(lines)}
        #{numbers_row(s)}
        #{categories_row(tag, total, prehandled, pre_rows)}
        #{prepared_row(ai)}
        #{team_row(s[:agents])}
        #{footer_row}

      </table>
      </td></tr></table>
      </body></html>
    HTML
  end

  # --- text ----------------------------------------------------------------

  # Fixed sentence templates. The first one doubles as the inbox preview text.
  def summary_lines(s, ai, prehandled)
    tag    = s[:tag_counts]
    total  = s[:created_total]
    closed = s[:closed_yesterday]

    lines = ["Gestern #{total == 1 ? 'ist 1 neues Ticket' : "sind #{total} neue Tickets"} eingegangen, #{closed} #{closed == 1 ? 'wurde' : 'wurden'} erledigt. Offen sind aktuell #{s[:open_now]} Tickets."]

    if total.positive?
      real = [total - prehandled, 0].max
      lines << "#{prehandled} von #{total} neuen Tickets (#{prehandled * 100 / total} %) hat Virtual Marketer vorab als Newsletter, automatische Meldung oder Creditreform erkannt. Sie brauchen keine Antwort."
      lines << "#{real} #{real == 1 ? 'Ticket braucht' : 'Tickets brauchen'} eine Bearbeitung durch das Team."
    end

    drafts = ai ? ai[:drafts] : 0
    lines << "Für #{drafts} #{drafts == 1 ? 'Ticket liegt ein Antwortentwurf' : 'Tickets liegt ein Antwortentwurf'} bereit. Das ist nur ein Vorschlag, es wird nichts automatisch gesendet." if drafts.positive?

    channels = []
    channels << "#{tag['voicemail']} #{tag['voicemail'] == 1 ? 'Voicemail' : 'Voicemails'}" if (tag['voicemail'] || 0).positive?
    channels << "#{tag['fax']} #{tag['fax'] == 1 ? 'Fax' : 'Faxe'}" if (tag['fax'] || 0).positive?
    if channels.any?
      singular = channels.size == 1 && [tag['voicemail'], tag['fax']].compact.sum == 1
      lines << "Darunter #{singular ? 'war' : 'waren'} #{channels.join(' und ')}."
    end

    auto = s[:agents].select { |a| a[:system] }.sum { |a| a[:solved] }
    lines << "#{auto} #{auto == 1 ? 'Ticket hat' : 'Tickets hat'} Virtual Marketer selbst geschlossen: automatische Meldungen ohne Anliegen, Phishing und Anrufe ohne Nachricht." if auto.positive?

    lines << "Gestern kamen mehr Tickets herein (#{total}) als erledigt wurden (#{closed})." if total > closed
    lines
  end

  # --- building blocks -----------------------------------------------------

  def header_row
    logo = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/apple-touch-icon.png"
    org  = Setting.get('organization').presence || 'Ticketsystem'
    <<~HTML
      <tr><td bgcolor="#{RED}" style="border-top:6px solid #{RED};font-size:0;line-height:0;background:#{RED};"></td></tr>
      <tr><td bgcolor="#ffffff" style="padding:22px #{PAD_X}px 20px;border-bottom:1px solid #{LINE};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
          <td width="56" valign="middle"><img src="#{h logo}" width="44" height="44" alt="Virtual Marketer" style="display:block;border:0;border-radius:10px;"></td>
          <td valign="middle">
            <div style="#{FONT}font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#{RED};">Tagesbericht</div>
            <div style="#{FONT}font-size:20px;font-weight:700;color:#{INK};line-height:1.25;margin-top:3px;">#{h long_date(date)}</div>
            <div style="#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin-top:2px;">Virtual Marketer für #{h org}</div>
          </td>
        </tr></table>
      </td></tr>
    HTML
  end

  def overview_row(lines)
    items = lines.map do |l|
      <<~LI
        <tr>
          <td width="18" valign="top" style="padding:0 0 9px;#{FONT}font-size:15px;line-height:1.5;color:#{RED};">&bull;</td>
          <td style="padding:0 0 9px;#{FONT}font-size:15px;line-height:1.5;color:#{INK};">#{h l}</td>
        </tr>
      LI
    end.join

    <<~HTML
      <tr><td bgcolor="#ffffff" style="padding:24px #{PAD_X}px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#{RED_SOFT}" style="background:#{RED_SOFT};border-left:4px solid #{RED};"><tr><td style="padding:18px 20px 10px;">
          <div style="#{FONT}font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#{RED};padding-bottom:10px;">Auf einen Blick</div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">#{items}</table>
        </td></tr></table>
      </td></tr>
    HTML
  end

  # label, title and a plain-language intro, then the section body.
  def section(label, title, intro, body)
    <<~HTML
      <tr><td bgcolor="#ffffff" style="padding:32px #{PAD_X}px 0;">
        <div style="#{FONT}font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#{RED};">#{h label}</div>
        <div style="#{FONT}font-size:20px;font-weight:700;color:#{INK};line-height:1.25;margin-top:4px;">#{h title}</div>
        <div style="#{FONT}font-size:14px;line-height:1.55;color:#{MUTED};margin-top:6px;">#{h intro}</div>
        #{body}
      </td></tr>
    HTML
  end

  def kpi_cell(value, label, note, side)
    pad = side == :left ? 'padding:0 6px 12px 0;' : 'padding:0 0 12px 6px;'
    <<~TD
      <td width="50%" valign="top" style="#{pad}">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#{CARD}" style="background:#{CARD};border-left:4px solid #{BLUE};"><tr><td style="padding:12px 12px 13px;">
          <div style="#{FONT}font-size:26px;font-weight:700;color:#{INK};line-height:1.15;">#{h value}</div>
          <div style="#{FONT}font-size:14px;font-weight:700;color:#{TEXT};margin-top:3px;">#{h label}</div>
          <div style="#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin-top:4px;">#{h note}</div>
        </td></tr></table>
      </td>
    TD
  end

  # --- sections ------------------------------------------------------------

  def numbers_row(s)
    first = if s[:first_response_measured] && s[:avg_first_response_minutes]
              duration_long(s[:avg_first_response_minutes])
            else
              'noch offen'
            end

    grid = <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;">
        <tr>
          #{kpi_cell(s[:created_total], 'Neue Tickets', 'Gestern eingegangen. Zusammengeführte Duplikate sind nicht mitgezählt.', :left)}
          #{kpi_cell(s[:closed_yesterday], 'Erledigt', 'Gestern auf Erledigt gesetzt, egal wann das Ticket eingegangen ist.', :right)}
        </tr>
        <tr>
          #{kpi_cell(s[:open_now], 'Offen insgesamt', 'Alle Tickets, die beim Erstellen dieses Berichts noch nicht erledigt waren, auch ältere.', :left)}
          #{kpi_cell(first, 'Erstantwort (Ø 30 Tage)', 'Zeit vom Eingang bis zur ersten Antwort an den Kunden, im Schnitt der letzten 30 Tage. Wird erst gemessen, seit das Postfach angebunden ist.', :right)}
        </tr>
      </table>
    HTML

    section('1 · Zahlen des Tages', 'Wie viel war los?', 'Die vier wichtigsten Zahlen für gestern.', grid)
  end

  def categories_row(tag, total, prehandled, pre_rows)
    return '' if total.zero?

    rows = CATEGORY_TAGS.filter_map do |t|
      n = tag[t] || 0
      n.positive? ? [CATEGORY_LABELS.fetch(t, t), n] : nil
    end.sort_by { |_, n| -n }
    max = [rows.map(&:last).max || 1, 1].max

    bars = rows.map do |label, n|
      px  = [(n * BAR_MAX_PX.to_f / max).round, 4].max
      pct = n * 100 / total
      <<~TR
        <tr>
          <td style="padding:8px 0 4px;#{FONT}font-size:14px;color:#{TEXT};">#{h label}</td>
          <td width="34" align="right" style="padding:8px 0 4px;#{FONT}font-size:14px;font-weight:700;color:#{INK};">#{n}</td>
          <td width="46" align="right" style="padding:8px 0 4px;#{FONT}font-size:12px;color:#{SOFT};">#{pct} %</td>
        </tr>
        <tr>
          <td colspan="3" style="padding:0 0 6px;"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="#{px}" style="width:#{px}px;border-top:12px solid #{BLUE};font-size:0;line-height:0;"></td></tr></table></td>
        </tr>
      TR
    end.join

    uncategorised = total - prehandled - rows.sum(&:last)
    notes = []
    notes << "#{uncategorised} #{uncategorised == 1 ? 'Ticket' : 'Tickets'} ohne erkannten Bereich sind nicht aufgeführt." if uncategorised.positive?
    notes << 'Voicemails und Faxe zählen zusätzlich in ihrem Bereich mit.' if (tag['voicemail'] || 0).positive? || (tag['fax'] || 0).positive?

    pre = ''
    if pre_rows.any?
      lines = pre_rows.map do |label, note, n|
        <<~TR
          <tr>
            <td valign="top" style="padding:6px 0;#{FONT}">
              <div style="font-size:14px;font-weight:700;color:#{TEXT};">#{h label}</div>
              <div style="font-size:12px;line-height:1.5;color:#{SOFT};margin-top:1px;">#{h note}</div>
            </td>
            <td width="34" valign="top" align="right" style="padding:6px 0;#{FONT}font-size:14px;font-weight:700;color:#{INK};">#{n}</td>
          </tr>
        TR
      end.join
      pre = <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#{CARD}" style="background:#{CARD};margin-top:18px;"><tr><td style="padding:14px 16px 10px;">
          <div style="#{FONT}font-size:14px;font-weight:700;color:#{INK};">Ohne Bearbeitung erkannt: #{prehandled}</div>
          <div style="#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin:3px 0 8px;">Diese Tickets hat Virtual Marketer sofort erkannt. Sie brauchen keine Antwort und stehen nicht in der Liste oben.</div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">#{lines}</table>
        </td></tr></table>
      HTML
    end

    body = <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:12px;">#{bars}</table>
      #{notes.any? ? "<div style=\"#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin-top:6px;\">#{h notes.join(' ')}</div>" : ''}
      #{pre}
    HTML

    section('2 · Themen', 'Worum ging es?',
            'Neue Tickets von gestern nach Themenbereich. Den Bereich erkennt Virtual Marketer aus dem Text der Nachricht, bei Voicemails aus der Aufnahme und bei Faxen aus dem Dokument. Der Prozentwert ist der Anteil an allen neuen Tickets.',
            body)
  end

  def prepared_row(ai)
    return '' if ai.nil? || ai[:tickets_with_note].zero?

    needs = ai[:needs_reply]
    pct   = needs.positive? ? (ai[:drafts] * 100 / needs) : 0

    items = [
      [needs,                'Tickets analysiert',     "Bereich, Anliegen und Kundendaten geprüft. Dazu kommen #{ai[:pre_handled]} Tickets, die ohne Bearbeitung erkannt wurden."],
      [ai[:drafts],          'Antwortentwürfe',        "#{pct} % der analysierten Tickets. Vorschlag für die Antwort an den Kunden, nur wenn belastbare Daten gefunden wurden."],
      [ai[:xentral_lookups], 'Abfragen in Xentral',    'Kunde, Auftrag, Rechnung oder Artikel nachgeschlagen, jeweils mit Link zum Datensatz in der Notiz.'],
      [ai[:customers_found], 'Kunden zugeordnet',      'Das Kundenkonto in Xentral wurde gefunden.'],
      [ai[:orders_found],    'Aufträge gefunden',      'Der genannte Auftrag existiert in Xentral.'],
      [ai[:invoices_found],  'Rechnungen gefunden',    'Die genannte Rechnung existiert in Xentral.'],
      [ai[:invoice_pdfs],    'Rechnungs-PDF angehängt', 'Bei Rechnungsanfragen liegt die Rechnung als PDF an der Notiz.'],
      [ai[:shop_links],      'Tickets mit Shop-Links', 'Produktseiten aus dem Shop, die zur Anfrage passen.'],
    ]

    rows = items.map do |value, label, note|
      color = value.positive? ? RED : '#a0aec0'
      <<~TR
        <tr>
          <td width="58" valign="top" style="padding:11px 0;border-bottom:1px solid #{LINE};#{FONT}font-size:26px;font-weight:700;line-height:1.1;color:#{color};">#{value}</td>
          <td valign="top" style="padding:11px 0;border-bottom:1px solid #{LINE};">
            <div style="#{FONT}font-size:14px;font-weight:700;color:#{TEXT};">#{h label}</div>
            <div style="#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin-top:2px;">#{h note}</div>
          </td>
        </tr>
      TR
    end.join

    body = <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;">#{rows}</table>
      <div style="#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};margin-top:10px;">Gezählt wird nach den internen Notizen, die Virtual Marketer gestern geschrieben hat.</div>
    HTML

    section('3 · Virtual Marketer', 'Was wurde vorbereitet?',
            'Virtual Marketer liest jedes neue Ticket, schlägt in Xentral nach und legt das Ergebnis als interne Notiz ins Ticket. Gesendet wird nichts: Antworten schreibt und verschickt das Team.',
            body)
  end

  def team_row(agents)
    return '' if agents.empty?

    # One card per person instead of a six-column table: six columns do not
    # fit a phone, and the mail is read on the phone as often as on the desk.
    sub  = "#{FONT}font-size:12px;color:#{SOFT};margin-top:2px;"
    stat = lambda do |label, value_html, width|
      "<td width=\"#{width}\" valign=\"top\" style=\"padding:8px 6px 0 0;#{FONT}\"><div style=\"font-size:11px;font-weight:700;letter-spacing:.6px;text-transform:uppercase;color:#{SOFT};\">#{label}</div>#{value_html}</td>"
    end
    num = ->(v, color = INK) { "<div style=\"font-size:16px;font-weight:700;margin-top:2px;color:#{v.to_i.positive? ? color : '#a0aec0'};\">#{v}</div>" }
    grid = ->(cells) { "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr>#{cells.join}</tr></table>" }

    rows = agents.map do |a|
      if a[:system]
        cards = grid.call([stat.call('Erledigt', num.call(a[:solved], GREEN), '33%'), stat.call('Offen', num.call(a[:open]), '67%')])
        name  = "<div style=\"#{FONT}font-size:15px;font-weight:700;color:#{SOFT};\">#{h a[:name]}</div><div style=\"#{sub}\">Automatik, keine Person: schließt Meldungen ohne Anliegen, Phishing und Anrufe ohne Nachricht</div>"
      else
        handled = if a[:first_at]
                    "<div style=\"font-size:16px;font-weight:700;margin-top:2px;color:#{INK};\">#{a[:tickets]}</div>#{a[:minutes_per_ticket] ? "<div style=\"#{sub}\">Ø #{duration_long(a[:minutes_per_ticket])}</div>" : ''}"
                  else
                    num.call(0)
                  end
        active = if a[:first_at]
                   "<div style=\"font-size:14px;margin-top:2px;color:#{TEXT};\">#{berlin(a[:first_at])} bis #{berlin(a[:last_at])}</div><div style=\"#{sub}\">#{duration_long(a[:active_minutes])} aktiv</div>"
                 else
                   "<div style=\"font-size:13px;margin-top:2px;color:#{SOFT};\">keine Aktivität</div>"
                 end
        reply = if a[:median_reply_minutes]
                  "<div style=\"font-size:14px;margin-top:2px;color:#{TEXT};\">#{duration_long(a[:median_reply_minutes])}</div><div style=\"#{sub}\">#{a[:replies]} #{a[:replies] == 1 ? 'Antwort' : 'Antworten'}</div>"
                else
                  "<div style=\"font-size:13px;margin-top:2px;color:#{SOFT};\">keine</div>"
                end
        cards = grid.call([stat.call('Erledigt', num.call(a[:solved], GREEN), '33%'), stat.call('Offen', num.call(a[:open]), '33%'), stat.call('Bearbeitet', handled, '34%')]) +
                grid.call([stat.call('Aktiv', active, '50%'), stat.call('Antwortzeit', reply, '50%')])
        name  = "<div style=\"#{FONT}font-size:15px;font-weight:700;color:#{INK};\">#{h a[:name]}</div>"
      end
      "<tr><td style=\"padding:14px 0;border-bottom:1px solid #{LINE};\">#{name}#{cards}</td></tr>"
    end.join

    legend = [
      ['Erledigt',     'Tickets, die die Person gestern auf Erledigt gesetzt hat, auch wenn sie niemandem zugewiesen waren. Bei Virtual Marketer sind es die automatisch geschlossenen Tickets. Die Liste ist danach sortiert, wer am meisten erledigt hat.'],
      ['Offen',        'Tickets, die der Person jetzt gehören und noch nicht erledigt sind.'],
      ['Bearbeitet',   'Tickets, in denen die Person gestern etwas geändert hat (Notiz, Antwort, Status, Zuweisung). Darunter die durchschnittliche aktive Zeit je Ticket.'],
      ['Aktiv',        "Von der ersten bis zur letzten Änderung. Pausen über #{ACTIVE_GAP_MINUTES} Minuten zählen nicht mit. Reines Ansehen eines Tickets wird nicht erfasst, die Zeit ist deshalb eher zu niedrig als zu hoch."],
      ['Antwortzeit',  'Mittlere Zeit (Median) von der letzten Kundennachricht bis zur Antwort per E-Mail, rund um die Uhr gerechnet, also mit Nacht und Wochenende.'],
    ].map do |term, text|
      "<tr><td width=\"88\" valign=\"top\" style=\"padding:3px 0;#{FONT}font-size:12px;font-weight:700;color:#{TEXT};\">#{term}</td><td valign=\"top\" style=\"padding:3px 0;#{FONT}font-size:12px;line-height:1.5;color:#{SOFT};\">#{h text}</td></tr>"
    end.join

    body = <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;border-top:2px solid #{LINE};">#{rows}</table>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#{CARD}" style="background:#{CARD};margin-top:16px;"><tr><td style="padding:12px 16px;">
        <div style="#{FONT}font-size:12px;font-weight:700;letter-spacing:.6px;text-transform:uppercase;color:#{SOFT};padding-bottom:4px;">So sind die Angaben gemeint</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">#{legend}</table>
      </td></tr></table>
    HTML

    section('4 · Team', 'Wer hat was getan?',
            'Was jede Person gestern im Ticketsystem getan hat, aus dem Änderungsprotokoll berechnet.',
            body)
  end

  def footer_row
    <<~HTML
      <tr><td bgcolor="#ffffff" style="padding:32px #{PAD_X}px 24px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid #{LINE};"><tr><td style="padding-top:16px;#{FONT}font-size:12px;line-height:1.6;color:#{SOFT};">
          Zahlen und Texte dieses Berichts werden nach festen Regeln aus den Ticketdaten berechnet, nichts davon wird geschätzt. Nur die Einordnung in Themenbereiche stammt von Virtual Marketer.<br>
          Erstellt automatisch am #{Time.zone.now.in_time_zone('Europe/Berlin').strftime('%d.%m.%Y um %H:%M')} Uhr. Fragen oder Wünsche zum Bericht: <a href="mailto:info@virtual-marketer.de" style="color:#{RED};text-decoration:underline;">info@virtual-marketer.de</a>
        </td></tr></table>
      </td></tr>
    HTML
  end

  # --- formatting ----------------------------------------------------------

  def long_date(d)
    "#{WEEKDAYS[d.wday]}, #{d.day}. #{MONTHS[d.month - 1]} #{d.year}"
  end

  def berlin(time)
    time.in_time_zone('Europe/Berlin').strftime('%H:%M')
  end

  # "unter 1 min", "34 min", "1 h 15 min", "1 Tag 21 h". Past a day the minutes
  # are dropped: nobody reads "45 h 24 min" faster than "1 Tag 21 h".
  def duration_long(minutes)
    return '' if minutes.nil?
    return 'unter 1 min' if minutes.zero?

    days, rest = minutes.divmod(1440)
    hours, mins = rest.divmod(60)
    return "#{days} #{days == 1 ? 'Tag' : 'Tage'} #{hours} h" if days.positive?

    hours.positive? ? "#{hours} h #{mins} min" : "#{mins} min"
  end

  def h(str)
    CGI.escapeHTML(str.to_s)
  end
end
