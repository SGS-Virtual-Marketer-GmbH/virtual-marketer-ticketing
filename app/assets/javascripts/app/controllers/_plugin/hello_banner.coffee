class HelloBanner
  # Upstream logs a Zammad ASCII banner + job-posting plug here on every
  # load. Suppressed: this is a rebranded instance, not Zammad's own.
  constructor: ->

App.Config.set('hello_banner', HelloBanner, 'Plugins')
