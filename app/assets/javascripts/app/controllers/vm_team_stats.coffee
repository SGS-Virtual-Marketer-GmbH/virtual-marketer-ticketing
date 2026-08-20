# The team board: per-agent numbers, for whoever leads the team.
#
# Only rendered for holders of the `report` permission. That check is repeated
# server-side in VMTeamStatsControllerPolicy — this one only decides whether the
# tab is worth drawing, it is not the gate.
#
# Sorting happens here rather than server-side so switching columns costs no
# round trip; the dataset is one row per agent.

class App.VmTeamStats extends App.Controller
  events:
    'click .js-vmPeriod': 'setPeriod'
    'click .js-vmSort':   'setSort'

  @PERIODS: [7, 30, 90]

  constructor: ->
    super
    @days    = 30
    @sortKey = 'open'
    @sortAsc = false
    @data    = null
    @error   = null
    @render()
    @fetch()

  render: =>
    @html App.view('vm_team_stats')(
      days:     @days
      periods:  App.VmTeamStats.PERIODS
      data:     @data
      error:    @error
      sortKey:  @sortKey
      sortAsc:  @sortAsc
      agents:   @sorted()
      duration: @formatDuration
    )

  fetch: =>
    @ajax(
      id:          'vm-team-stats'
      type:        'GET'
      url:         "#{@apiPath}/vm_team_stats?days=#{@days}"
      processData: true
      success: (data) =>
        @error = null
        @data  = data
        @render()
      error: (xhr) =>
        @data  = null
        @error = if xhr.status is 403 then __('Für diese Auswertung fehlen dir die Rechte.') else __('Die Auswertung konnte nicht geladen werden.')
        @render()
    )

  setPeriod: (e) =>
    e.preventDefault()
    days = parseInt($(e.currentTarget).data('days'), 10)
    return if !days or days is @days
    @days = days
    @fetch()

  setSort: (e) =>
    e.preventDefault()
    key = $(e.currentTarget).data('key')
    return if !key
    if key is @sortKey
      @sortAsc = !@sortAsc
    else
      @sortKey = key
      # Names read best A-Z, counts and durations read best worst-first.
      @sortAsc = key is 'name'
    @render()

  sorted: =>
    return [] if !@data or !@data.agents
    rows = @data.agents.slice()
    rows.sort (a, b) =>
      # Automation accounts stay at the bottom in every sort order. Sorted in
      # with the team they would top the "offen" column with several hundred
      # tickets and read as a colleague who is hopelessly behind.
      return 1  if a.system and not b.system
      return -1 if b.system and not a.system

      left  = a[@sortKey]
      right = b[@sortKey]
      # A missing average is not a small one. Park those rows at the end
      # regardless of direction, so an agent with no measured data never looks
      # like the fastest in the team.
      return 1  if !left? and right?
      return -1 if left? and !right?
      return 0  if !left? and !right?
      if _.isString(left)
        result = left.localeCompare(right)
      else
        result = left - right
      if @sortAsc then result else -result
    rows

  # Minutes to something a person reads at a glance. Deliberately coarse:
  # "4,2 Std." is the useful precision, "252 Min." is not.
  formatDuration: (minutes) ->
    return '—' if !minutes? or minutes < 0
    return "#{minutes} Min." if minutes < 90
    hours = minutes / 60
    return "#{hours.toFixed(1).replace('.', ',')} Std." if hours < 48
    days = hours / 24
    "#{days.toFixed(1).replace('.', ',')} Tage"
