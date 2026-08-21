# The "KI-Kollegen" board on the dashboard.
#
# One tile per ticket category, each saying in plain German what the assistant
# already does for that kind of ticket, which systems it reads to do it, and how
# many tickets are waiting right now. Clicking a tile opens that category's
# queue.
#
# The wording is deliberately concrete. "Beantwortet Lieferstatus-Fragen mit
# Live-Tracking" is checkable and, if it stops being true, someone notices.
# "Nutzt KI für besseren Service" is not, and nobody ever notices.
#
# Counts come from /ticket_overviews, which is already scoped to the logged-in
# agent's groups — so the numbers on the board are the same numbers in the
# sidebar, and an agent never sees a count for a queue they cannot open.
#
# Artwork is inline SVG on purpose: it inherits the surrounding colour, stays
# sharp at any zoom and on any display, needs no build step and no external
# request. A PNG set would be four files per tile and blurry on the fifth
# display someone plugs in.

class App.VmAgentTiles extends App.Controller
  events:
    'click .js-vmTile': 'openOverview'

  # Each entry: the overview slug it opens, what it does, what it can do, and
  # which sources it reads. `sources` are the real ones from the pipeline
  # (docs/DATA_SOURCES.md) — not a wish list.
  @TILES: [
    {
      key: 'bestellung'
      name: __('Bestellungen')
      icon: 'cart'
      description: __('Nimmt Bestellungen, Änderungen und Bestellbestätigungen auf, findet den Auftrag in Xentral und schlägt die Antwort vor.')
      can: [__('Auftrag finden'), __('Antwortentwurf')]
      sees: [__('Aufträge'), __('Kunden'), __('Artikel')]
    }
    {
      key: 'lieferung-versand'
      name: __('Lieferauskunft')
      icon: 'truck'
      description: __('Beantwortet Fragen zu Lieferung und Verbleib einer Sendung — mit echtem Paketstatus und Tracking-Link, nicht mit einer Vermutung.')
      can: [__('Sendung verfolgen'), __('Rückstand prüfen'), __('Antwortentwurf')]
      sees: [__('Paqato'), __('GLS Dental'), __('Dental Union'), __('Aufträge')]
    }
    {
      key: 'storno'
      name: __('Stornierungen')
      icon: 'cancel'
      description: __('Prüft Stornoanfragen gegen den echten Auftragsstand und erkennt, ob beim Großhändler bereits storniert wurde.')
      can: [__('Stornostatus prüfen'), __('Antwortentwurf')]
      sees: [__('GLS-Stornodaten'), __('Aufträge')]
    }
    {
      key: 'retouren'
      name: __('Retouren')
      icon: 'return'
      description: __('Bearbeitet Rückgaben und Retourenanfragen — liest dazu auch den angehängten Retourenschein, wenn im Text selbst nichts steht.')
      can: [__('Auftrag finden'), __('PDF lesen'), __('Antwortentwurf')]
      sees: [__('Aufträge'), __('Kunden'), __('Artikel')]
    }
    {
      key: 'reklamation'
      name: __('Reklamationen')
      icon: 'damage'
      description: __('Nimmt Falschlieferungen und Transportschäden auf, ordnet sie dem Lieferschein zu und bereitet die Antwort vor.')
      can: [__('Lieferung finden'), __('Bilder lesen'), __('Antwortentwurf')]
      sees: [__('Lieferungen'), __('Aufträge'), __('Kunden')]
    }
    {
      key: 'zahlung'
      name: __('Rechnung & Zahlung')
      icon: 'invoice'
      description: __('Ordnet Rechnungs-, Zahlungs- und Mahnungsanfragen der richtigen Rechnung zu und verlinkt sie direkt in Xentral.')
      can: [__('Rechnung finden'), __('Antwortentwurf')]
      sees: [__('Rechnungen'), __('Kunden')]
    }
    {
      key: 'technik'
      name: __('Technik')
      icon: 'wrench'
      description: __('Erkennt Wartungs- und Reparaturanliegen, findet das betroffene Gerät und leitet an die Technik weiter.')
      can: [__('Gerät finden'), __('Weiterleitung')]
      sees: [__('Artikel'), __('Kunden'), __('Aufträge')]
    }
    {
      key: 'vertrieb'
      name: __('Produktberatung')
      icon: 'tag'
      description: __('Beantwortet Produkt-, Verfügbarkeits- und Angebotsfragen, ohne interne Daten preiszugeben.')
      can: [__('Artikel finden'), __('Antwortentwurf')]
      sees: [__('Artikel'), __('Kunden')]
    }
    {
      key: 'allgemeine-dumme-fragen'
      name: __('Allgemeiner Kundenservice')
      icon: 'headset'
      description: __('Die Eingangsstelle: sichtet jede Anfrage, verteilt sie an die passende Kategorie und übernimmt alles, was sonst nirgends eindeutig hingehört.')
      can: [__('Einsortieren'), __('Weiterleitung'), __('Antwortentwurf')]
      sees: [__('alle Fachbereiche')]
    }
    {
      key: 'voicemail'
      name: __('Rückrufe')
      icon: 'mic'
      description: __('Schreibt jede Anrufbeantworter-Nachricht mit und sortiert sie nach dem, was gesagt wurde — mit Rückrufnummer aus der Anlage.')
      can: [__('Transkription'), __('Rückrufnummer'), __('Einsortieren')]
      sees: [__('Telefonanlage'), __('Kunden')]
      highlight: true
    }
    {
      key: 'fax'
      name: __('Faxe')
      icon: 'fax'
      description: __('Liest das angehängte Fax-PDF und zieht Kunden-, Auftrags- und Artikelnummern heraus, die im Ticket selbst gar nicht stehen.')
      can: [__('PDF lesen'), __('Nummern erkennen'), __('Einsortieren')]
      sees: [__('Fax-Anhang'), __('Aufträge'), __('Artikel')]
      highlight: true
    }
  ]

  constructor: ->
    super
    @counts = {}
    @render()
    @fetchCounts()

  render: =>
    @html App.view('vm_agent_tiles')(
      tiles:  App.VmAgentTiles.TILES
      counts: @counts
      icon:   (name) -> App.VmAgentTileIcons[name] or ''
    )

  # One request for every tile's number. The endpoint already applies the
  # agent's own group permissions, so nothing here has to re-check them.
  fetchCounts: =>
    @ajax(
      id:    'vm-agent-tile-counts'
      type:  'GET'
      url:   "#{@apiPath}/ticket_overviews?view_mode=s"
      processData: true
      success: (data) =>
        return if !_.isArray(data)
        @counts = {}
        for row in data
          @counts[row.link] = row.count
        @render()
      # A failed count must not blank the board — the tiles still explain what
      # the assistant does, which is most of their value.
      error: =>
        @log 'error', 'Kachelzähler konnten nicht geladen werden'
    )

  # A tile opens the workspace for that category, not the bare overview list:
  # the queue is there too, but with the ticket and the assistant beside it,
  # which is the point of clicking a tile in the first place. The plain
  # overviews stay reachable from the sidebar for anyone who prefers them.
  openOverview: (e) =>
    e.preventDefault()
    link = $(e.currentTarget).data('link')
    return if !link
    @navigate "#vm_work/#{link}"
