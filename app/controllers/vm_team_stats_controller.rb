# Per-agent numbers for team leads.
#
# Zammad's own Reporting module cannot answer "who handled how many": it charts
# metrics over time filtered by a profile, and a profile is just a condition —
# there is no per-agent dimension, so you would need one profile per person.
# It also requires Elasticsearch (Report.enabled? checks es_url), which this
# installation deliberately runs without. Hence this controller: plain SQL over
# the ticket table, no search index involved.
#
# Gated on the `report` permission, not on `admin`, so team leads can be given
# the view through a role without also handing them the admin interface.
#
# Deliberately NOT scoped to the viewer's groups. An agent sees their own
# numbers on the dashboard; this view is the whole team by definition, which is
# exactly why it sits behind a permission most agents do not hold.

class VmTeamStatsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # A session row is written on real request activity, so it tracks presence
  # closely. Measured against the live instance: sessions.updated_at was current
  # to the second, while taskbars.last_contact was hours stale — which is why
  # presence is read from sessions and not from the taskbar.
  ONLINE_WINDOW = 5.minutes

  DEFAULT_DAYS = 30
  MAX_DAYS     = 365

  # Automation accounts, not colleagues. Both hold the agent permission and own
  # real tickets, so they cannot simply be dropped — this pipeline's own account
  # currently owns several hundred — but averaging a person against a machine
  # makes the column meaningless. They are listed last and flagged instead of
  # hidden, because a leadership view that silently omits hundreds of tickets is
  # worse than one that labels them.
  #
  # Matched by login: there is no "is a bot" flag in Zammad, and last_login does
  # not work as a proxy — both of these have one (imported from Zendesk) while
  # four real colleagues have never logged in.
  SYSTEM_ACCOUNT_LOGINS = [
    'info@virtual-marketer.de',   # this pipeline
    'ai@the-platform-group.com',  # the-platform-group's own automation
  ].freeze

  # GET /api/v1/vm_team_stats?days=30
  def show
    render json: {
      days:            days,
      since:           since,
      generated_at:    Time.zone.now,
      unassigned_open: unassigned_open,
      # Straight from the data rather than assumed: first_response_at is only
      # ever set for a public agent reply sent from this system, so until the
      # mailbox is switched over there is nothing to average and the column
      # would otherwise just be a wall of dashes with no explanation.
      #
      # Derived from the rows rather than from a raw ticket count on purpose:
      # the live instance has four tickets carrying a first_response_at, and all
      # four are owned by nobody. Counting those would suppress the hint while
      # every single agent row still showed "—".
      first_response_measured: rows.any? { |row| row[:first_response_minutes] },
      agents:          rows,
    }
  end

  private

  def days
    @days ||= begin
      requested = params[:days].to_i
      requested.between?(1, MAX_DAYS) ? requested : DEFAULT_DAYS
    end
  end

  def since
    @since ||= days.days.ago
  end

  def agent_users
    @agent_users ||= User
      .with_permissions('ticket.agent')
      .where(active: true)
      .where.not(id: 1) # the system user, which owns no real work
      .distinct
      .sort_by { |user| [SYSTEM_ACCOUNT_LOGINS.include?(user.login) ? 1 : 0, user.fullname.downcase] }
  end

  def rows
    @rows ||= begin
      online  = online_user_ids
      open    = open_counts
      closed  = closed_rows
      replied = first_response_rows

      agent_users.map do |user|
        done = closed[user.id] || []
        first = replied[user.id] || []

        {
          id:                     user.id,
          name:                   user.fullname,
          system:                 SYSTEM_ACCOUNT_LOGINS.include?(user.login),
          online:                 online.include?(user.id),
          open:                   open[user.id] || 0,
          solved:                 done.length,
          # Nil rather than zero when there is nothing to average — the view
          # renders that as a dash, which is honest about "no data" where a 0
          # would read as "instant".
          resolution_minutes:     average_minutes(done),
          first_response_minutes: average_minutes(first),
        }
      end
    end
  end

  def open_state_ids
    @open_state_ids ||= Ticket::State.by_category_ids(:open)
  end

  def open_counts
    Ticket.where(state_id: open_state_ids).group(:owner_id).count
  end

  def unassigned_open
    Ticket.where(state_id: open_state_ids, owner_id: 1).count
  end

  # { owner_id => [minutes, ...] } for tickets closed inside the period.
  def closed_rows
    Ticket
      .where(close_at: since..)
      .pluck(:owner_id, :created_at, :close_at)
      .each_with_object({}) do |(owner_id, created_at, close_at), acc|
        (acc[owner_id] ||= []) << ((close_at - created_at) / 60.0)
      end
  end

  # { owner_id => [minutes, ...] } for first replies sent inside the period.
  def first_response_rows
    Ticket
      .where(first_response_at: since..)
      .pluck(:owner_id, :created_at, :first_response_at)
      .each_with_object({}) do |(owner_id, created_at, responded_at), acc|
        (acc[owner_id] ||= []) << ((responded_at - created_at) / 60.0)
      end
  end

  def average_minutes(values)
    return nil if values.blank?

    (values.sum / values.length).round
  end

  def online_user_ids
    ActiveRecord::SessionStore::Session
      .where(updated_at: ONLINE_WINDOW.ago..)
      .filter_map { |session| session.data['user_id'] }
      .uniq
  end
end
