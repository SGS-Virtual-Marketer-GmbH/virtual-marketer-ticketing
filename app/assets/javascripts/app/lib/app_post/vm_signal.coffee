# One glance at a ticket: is the next move ours, or are we waiting?
#
# The ticket state alone cannot say that. "In Bearbeitung" is the same state
# whether the customer has just answered (we are on turn) or we have just
# written to them (they are). The answer is in two timestamps the client already
# has on every ticket, last_contact_customer_at and last_contact_agent_at, so
# this works from the queue list without one extra request.
#
# Rule of thumb, and the only visual rule: a FILLED badge means "we are on
# turn", an OUTLINED, muted badge means "we are waiting". Colour is never the
# only carrier; every signal has an icon and a text label as well.
#
# First match wins:
#
#   closed                                          -> null (no signal)
#   state new                                       -> neu             (ours)
#   customer wrote after the last agent contact     -> antwort         (ours)
#   state clarification                             -> wartet_kollege  (waiting)
#   agent contact after the last customer contact   -> wartet_kunde    (waiting)
#   anything else                                   -> arbeit          (ours)
#
# "antwort" deliberately beats "clarification": a customer reply does not
# change the state, so a ticket parked with a colleague would otherwise stay
# grey while the customer is waiting for an answer.
#
# Which state names mean what is configuration, not code, so another customer
# with differently named states can reuse this: set vm_signal_map (any subset
# of the keys in DEFAULTS) with App.Config.set. The pure decision lives in
# @decide(), which touches neither the DOM nor the state collection.

class App.VmSignal

  @DEFAULTS:
    # App.TicketState names, per role
    closed:    ['closed', 'merged', 'removed']
    fresh:     ['new']
    colleague: ['clarification']
    # false: an answered ticket is just "In Arbeit" again instead of "Wartet auf Kunde"
    waitingForCustomer: true

  # Shown order in the queue, most urgent first. Closed tickets go last.
  @ORDER: ['neu', 'antwort', 'arbeit', 'wartet_kollege', 'wartet_kunde']

  @SIGNALS:
    neu:            { label: __('Neu'),               icon: 'dot',     ourTurn: true  }
    antwort:        { label: __('Antwort da'),        icon: 'arrow-in', ourTurn: true  }
    arbeit:         { label: __('In Arbeit'),         icon: 'gear',    ourTurn: true  }
    wartet_kollege: { label: __('Wartet auf Kollegen'), icon: 'hourglass', ourTurn: false }
    wartet_kunde:   { label: __('Wartet auf Kunde'),  icon: 'clock',   ourTurn: false }

  # 24x24, stroke currentColor, same house style as the other VM icons.
  @ICONS:
    'dot':       '<circle cx="12" cy="12" r="6" fill="currentColor" stroke="none"/>'
    'arrow-in':  '<path d="M19 5L6 18M6 9v9h9"/>'
    'gear':      '<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/>'
    'hourglass': '<path d="M7 3h10M7 21h10M8 3v3.5L12 12l-4 5.5V21M16 3v3.5L12 12l4 5.5V21"/>'
    'clock':     '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'

  @config: ->
    custom = App.Config.get('vm_signal_map')
    _.extend({}, @DEFAULTS, if _.isObject(custom) then custom else {})

  # The signal of a ticket model: { key, label, icon, ourTurn }, or null when
  # the ticket is closed or has no state yet.
  @of: (ticket) ->
    return null if !ticket
    state = if ticket.state_id then App.TicketState.find(ticket.state_id) else null
    @decide(state?.name, ticket.last_contact_customer_at, ticket.last_contact_agent_at, @config())

  # The decision itself. Timestamps are anything Date can parse (ISO strings
  # from the API); empty means "never".
  @decide: (stateName, customerAt, agentAt, config = @DEFAULTS) ->
    return null if !stateName or stateName in config.closed

    customer = @time(customerAt)
    agent    = @time(agentAt)

    key =
      if stateName in config.fresh
        'neu'
      else if customer? and (!agent? or customer > agent)
        'antwort'
      else if stateName in config.colleague
        'wartet_kollege'
      else if config.waitingForCustomer and agent? and (!customer? or agent > customer)
        'wartet_kunde'
      else
        'arbeit'

    @signal(key)

  @signal: (key) ->
    base = @SIGNALS[key]
    { key: key, label: base.label, icon: base.icon, ourTurn: base.ourTurn }

  # null for empty or unparsable, so "no timestamp" never compares as 0.
  @time: (value) ->
    return null if !value
    t = new Date(value).getTime()
    if isNaN(t) then null else t

  # Position in the queue; closed (null) sorts last.
  @rank: (signal) ->
    return @ORDER.length if !signal
    index = @ORDER.indexOf(signal.key)
    if index < 0 then @ORDER.length else index

  # Stable sort: tickets with the same signal keep the order they came in.
  @sort: (tickets) ->
    ranked = ({ ticket: ticket, rank: @rank(@of(ticket)), index: index } for ticket, index in tickets)
    ranked.sort((a, b) -> a.rank - b.rank or a.index - b.index)
    (entry.ticket for entry in ranked)

  # The badge markup. Label and title are static, translated strings.
  @badge: (signal) ->
    return '' if !signal
    label = App.i18n.translateContent(signal.label)
    "<span class=\"vm-sig vm-sig--#{signal.key} #{if signal.ourTurn then 'vm-sig--on' else 'vm-sig--off'}\" title=\"#{label}\">" +
      "<svg class=\"vm-sig__icon\" viewBox=\"0 0 24 24\" aria-hidden=\"true\">#{@ICONS[signal.icon]}</svg>" +
      "<span class=\"vm-sig__label\">#{label}</span></span>"
