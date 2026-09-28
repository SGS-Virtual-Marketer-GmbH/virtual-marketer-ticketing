# Ticket counts for the VM board and workspace, per overview and per agent.
#
# GET /api/v1/ticket_overviews already computes counts on demand, but only the
# total per overview. The board's "Nur meine Tickets" switch also needs, for
# every category, how many of those tickets belong to the current agent and
# how many belong to nobody yet, so that a category that looks empty in the
# "mine" view can say what it is hiding. Computing that in the browser would
# mean fetching every category's full ticket list on every refresh.
#
# The counts are built from exactly the same query as Ticket::Overviews.index
# (same overviews, same permission scope, same condition), so `count` here is
# the number GET /ticket_overviews reports and the list endpoint returns. The
# two extra numbers are that query narrowed by owner.
#
# `only_mine` is the agent's stored choice for the switch (user preference
# `vm_only_mine`), or, as long as they have never chosen, the default: off for
# everyone. It used to default on for non-admins, which on 2026-09-28's real
# data hid nearly the whole queue (141 of 143 open tickets have no owner) from
# any agent who had not already self-assigned tickets. An agent who already
# has a stored choice, on or off, keeps it -- this only changes what someone
# with no choice yet sees.
#
# `intro_seen` is the same kind of stored, per-user, server-side flag (user
# preference `vm_intro_seen`) for the one-time hint that explains the "Meine
# Tickets" tile and this switch. Also treated as seen once the agent has a
# stored `only_mine` choice of their own: having already used the switch is
# itself proof they do not need the hint, and it keeps the hint from
# reappearing for someone whose choice was set by testing rather than by
# clicking the hint's own dismiss button.
class VmCountsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # Zammad's "nobody" user. Unassigned tickets carry owner_id 1, rarely NULL.
  NOBODY_ID = 1

  def index
    user = current_user
    overviews = Ticket::Overviews.all(current_user: user)

    scopes = {
      read:     TicketPolicy::ReadScope.new(user).resolve,
      overview: TicketPolicy::OverviewScope.new(user).resolve,
    }

    rows = overviews.map do |overview|
      params = Ticket::Overviews._db_query_params(overview, user)
      scope  = overview.condition['ticket.mention_user_ids'].present? ? scopes[:read] : scopes[:overview]
      base   = scope
        .distinct
        .where(params.query_condition, *params.bind_condition)
        .joins(params.tables)

      {
        link:       overview.link,
        name:       overview.name,
        count:      base.count,
        mine:       base.where(tickets: { owner_id: user.id }).count,
        unassigned: base.where(tickets: { owner_id: [nil, NOBODY_ID] }).count,
      }
    end

    render json: {
      counts:           rows,
      only_mine:        only_mine(user),
      only_mine_chosen: !stored_only_mine(user).nil?,
      intro_seen:       intro_seen(user),
    }
  end

  private

  # PUT /users/preferences stores a key as a symbol; read it either way.
  def stored_pref(user, key)
    prefs = user.preferences || {}
    prefs.key?(key) ? prefs[key] : prefs[key.to_s]
  end

  def stored_only_mine(user)
    stored_pref(user, :vm_only_mine)
  end

  def only_mine(user)
    stored = stored_only_mine(user)
    return ActiveModel::Type::Boolean.new.cast(stored) if !stored.nil?

    false
  end

  def intro_seen(user)
    return true if !stored_only_mine(user).nil?

    ActiveModel::Type::Boolean.new.cast(stored_pref(user, :vm_intro_seen)) || false
  end
end
