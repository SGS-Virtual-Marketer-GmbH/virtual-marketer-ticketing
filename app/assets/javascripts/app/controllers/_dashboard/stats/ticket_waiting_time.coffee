class Stats extends App.ControllerDashboardStatsBase
  render: (data = {}) ->
    if !data.StatsTicketWaitingTime
      data.StatsTicketWaitingTime =
        handling_time: 0
        average: 0
        state: 'supergood'
        average_per_agent: 0

    data.StatsTicketWaitingTime.description = __('How long did each customer have to wait, on average, to get a response from you today?')

    content = App.view('dashboard/stats/ticket_waiting_time')(data)
    if @$('.ticket_waiting_time').length > 0
      @$('.ticket_waiting_time').html(content)
    else
      @el.append(content)

    if data.StatsTicketWaitingTime
      @renderWidgetClockFace(data.StatsTicketWaitingTime.handling_time, data.StatsTicketWaitingTime.state, data.StatsTicketWaitingTime.percent)

  renderWidgetClockFace: (time, state, percent) =>
    dpr = window.devicePixelRatio || 1
    canvas = @el.find 'canvas'
    ctx    = canvas.get(0).getContext '2d'
    radius = 26

    @el.find('.time.stat-widget .stat-amount').text time

    canvas.attr 'width', 2 * radius * dpr
    canvas.attr 'height', 2 * radius * dpr

    # scale canvas to dpr (2x on retina)
    ctx.scale dpr, dpr

    handlingTimeColors = {}
    handlingTimeColors['supergood'] = '#38AE6A' # supergood
    handlingTimeColors['good']      = '#A9AC41' # good
    handlingTimeColors['ok']        = '#FAAB00' # ok
    handlingTimeColors['bad']       = '#F6820B' # bad
    handlingTimeColors['superbad']  = '#F35910' # superbad

    for handlingState, timeColor of handlingTimeColors
      if state == handlingState
        backgroundColor = timeColor
        break

    # Faint background ring/pie: deliberately translucent throughout (not just
    # this base layer) so the state colour reads as a subtle wash sitting on
    # top of the backdrop icon (.stopwatch-icon) rather than a solid, dominant
    # disc that hides it -- see the .stat-dial CSS comment for the sizing half
    # of the same fix.
    if time isnt 0
      ctx.globalAlpha = 0.22
    ctx.fillStyle = backgroundColor
    ctx.beginPath()
    ctx.arc radius, radius, radius, 0, Math.PI * 2, true
    ctx.closePath()
    ctx.fill()

    # Progress pie piece, still translucent -- readable, but see-through
    # enough that it never fully hides the icon underneath it.
    ctx.globalAlpha = 0.72

    ctx.beginPath()
    ctx.moveTo radius, radius
    arcsector = Math.PI * 2 * percent
    ctx.arc radius, radius, radius, -Math.PI/2, arcsector - Math.PI/2, false
    ctx.lineTo radius, radius
    ctx.closePath()
    ctx.fill()

App.Config.set('ticket_waiting_time', { controller: Stats, permission: 'ticket.agent', prio: 100, className: 'ticket_waiting_time' }, 'Stats')
