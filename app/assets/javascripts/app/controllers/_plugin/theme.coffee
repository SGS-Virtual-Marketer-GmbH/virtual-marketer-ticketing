class App.Theme extends App.Controller
  constructor: ->
    super

    return if window.location.href.includes('/tests_')

    mediaQueryList = window.matchMedia('(prefers-color-scheme: dark)')
    if typeof mediaQueryList.addEventListener is 'function'
      mediaQueryList.addEventListener('change', @onMediaQueryChange)

    @controllerBind('ui:theme:set', @set)
    @controllerBind('ui:theme:toggle-dark-mode', @toggleDarkMode)
    @set(
      theme: @currentTheme()
    )

  # Virtual Marketer is a light brand — the palette, the logo lockup and the
  # printed material are all built on a light surface. So "auto" resolves to
  # light regardless of the operating system's preference, instead of handing
  # anyone on a dark-mode desktop a product that does not look like the brand.
  #
  # This is the DEFAULT, not a lock: a user who explicitly picks dark in their
  # profile still gets dark, because currentTheme() checks the stored
  # preference before it ever reaches here.
  auto: ->
    'light'

  currentTheme: (theme) =>
    theme ||= App.Session.get('preferences')?.theme

    switch theme
      when 'dark'
        'dark'
      when 'light'
        'light'
      else
        @auto()

  onMediaQueryChange: (event) =>
    @set(
      theme: @currentTheme()
    )

  toggleDarkMode: =>
    @set(
      theme: if document.documentElement.dataset.theme == 'dark' then 'light' else 'dark'
      save: true
    )

  set: (data) =>
    if data.save && App.Session.get()?.id
      App.Ajax.request(
        id:          'preferences'
        type:        'PUT'
        url:         "#{App.Config.get('api_path')}/users/preferences"
        data:        JSON.stringify(theme: data.theme)
        processData: true
      )
      App.Event.trigger('ui:theme:saved', data)

    document.documentElement.dataset.theme = @currentTheme(data.theme)
    document.documentElement.style.colorScheme = @currentTheme(data.theme)
    App.Event.trigger('ui:theme:changed', data)

App.Config.set('theme', App.Theme, 'Plugins')
