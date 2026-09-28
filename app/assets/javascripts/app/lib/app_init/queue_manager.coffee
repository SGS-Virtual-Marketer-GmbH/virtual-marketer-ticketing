class App.QueueManager
  _instance = undefined

  @init: ->
    _instance ?= new _queueSingleton

  @add: (key, data) ->
    if _instance == undefined
      _instance ?= new _queueSingleton
    _instance.add(key, data)

  @pull: (key) ->
    if _instance == undefined
      _instance ?= new _queueSingleton
    _instance.pull(key)

  @all: (key) ->
    if _instance == undefined
      _instance ?= new _queueSingleton
    _instance.all(key)

  @run: (key, callback) ->
    if _instance == undefined
      _instance ?= new _queueSingleton
    _instance.run(key, callback)

class _queueSingleton
  constructor: ->
    @queues = {}
    @queueRunning = {}

  add: (key, data) ->
    if !@queues[key]
      @queues[key] = []
    @queues[key].push data
    true

  pull: (key) ->
    return if !@queues[key]
    @queues[key].shift()

  all: (key) ->
    @queues[key]

  run: (key, callback) ->
    return if !@queues[key]
    return if @queueRunning[key]
    localQueue = @queues[key]
    return if _.isEmpty(localQueue)
    # A callback that throws used to leave queueRunning[key] true forever:
    # every later run() for that key returned early, so the key's subscribers
    # (e.g. the overview counts) got nothing until the page was reloaded, and
    # a logout/login did not help. Each callback is now isolated and the flag
    # is always reset.
    @queueRunning[key] = true
    try
      while localQueue.length
        item = localQueue.shift()
        try
          item()
        catch e
          console?.error?("App.QueueManager: callback in queue '#{key}' failed", e)
    finally
      @queueRunning[key] = false
    true
