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
# `vm_only_mine`), or, as long as they have never chosen, the default: on for
# agents without the Admin role, off for admins.
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
    }
  end

  private

  # PUT /users/preferences stores the key as a symbol; read it either way.
  def stored_only_mine(user)
    prefs = user.preferences || {}
    prefs.key?(:vm_only_mine) ? prefs[:vm_only_mine] : prefs['vm_only_mine']
  end

  def only_mine(user)
    stored = stored_only_mine(user)
    return ActiveModel::Type::Boolean.new.cast(stored) if !stored.nil?

    !user.role?('Admin')
  end
end
