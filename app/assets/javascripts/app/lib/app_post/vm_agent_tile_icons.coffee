# Artwork for the KI-Kollegen tiles.
#
# Drawn here rather than shipped as image files: inline SVG inherits the tile's
# colour (so it follows the brand palette and any future theme without a second
# asset set), stays sharp at every zoom level and on every display, and costs no
# extra request. A raster set would mean several files per tile, each one wrong
# on the next display someone plugs in.
#
# House style, kept identical across all of them so the board reads as one set:
#   * 24x24 viewBox, no fill, stroke: currentColor, stroke-width 1.6
#   * round caps and joins
#   * one clear silhouette per icon — these are read at 40px, not studied
#
# Referenced by name from App.VmAgentTiles.TILES.

W = 'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"'

App.VmAgentTileIcons =
  # Bestellungen — a basket, the plainest possible "an order came in".
  cart: """
    <svg #{W}><path d="M3 4h2.2l2.1 10.4a1.6 1.6 0 0 0 1.6 1.3h7.9a1.6 1.6 0 0 0 1.6-1.2L20 7.5H6.2"/>
    <circle cx="9.5" cy="19.5" r="1.3"/><circle cx="17" cy="19.5" r="1.3"/></svg>
  """

  # Lieferauskunft — a box in transit.
  truck: """
    <svg #{W}><path d="M2.5 6.5h10.2v9H2.5z"/><path d="M12.7 9.8h3.6l3.2 3v2.7h-6.8z"/>
    <circle cx="6.4" cy="18" r="1.6"/><circle cx="16.6" cy="18" r="1.6"/></svg>
  """

  # Stornierungen — struck through, not deleted: the order still exists.
  cancel: """
    <svg #{W}><circle cx="12" cy="12" r="8.4"/><path d="M6.6 6.6l10.8 10.8"/></svg>
  """

  # Retouren — the parcel coming back.
  return: """
    <svg #{W}><path d="M4 8.6h11.4a4.4 4.4 0 1 1 0 8.8H8.2"/><path d="M7.4 5.2L4 8.6l3.4 3.4"/></svg>
  """

  # Reklamationen — a damaged box. The crack is the whole message.
  damage: """
    <svg #{W}><path d="M4 7.6l8-3.6 8 3.6v8.8l-8 3.6-8-3.6z"/><path d="M12 4v4.6l-2.4 2 2.4 2.2-1.6 3"/></svg>
  """

  # Rechnung & Zahlung — a document with a torn edge, i.e. a bill.
  invoice: """
    <svg #{W}><path d="M6 3.2h9.2L19 7v13.8l-2.2-1.4-2.2 1.4-2.2-1.4-2.2 1.4L8 19.4 6 20.8z"/>
    <path d="M15 3.2V7h4"/><path d="M9 10.4h6.4M9 13.6h4.2"/></svg>
  """

  # Technik — maintenance and repair, not product questions.
  wrench: """
    <svg #{W}><path d="M15.6 3.6a5 5 0 0 0-5.9 6.4L3.4 16.3a2 2 0 1 0 2.8 2.8l6.3-6.3a5 5 0 0 0 6.4-5.9l-2.9 2.9-2.6-.7-.7-2.6z"/></svg>
  """

  # Produktberatung — a product tag.
  tag: """
    <svg #{W}><path d="M11 3.4H20v9l-8.4 8.4a1.6 1.6 0 0 1-2.3 0l-6.7-6.7a1.6 1.6 0 0 1 0-2.3z"/>
    <circle cx="16.2" cy="7.8" r="1.4"/></svg>
  """

  # Allgemeiner Kundenservice — the front desk.
  headset: """
    <svg #{W}><path d="M4.4 14.6v-2.8a7.6 7.6 0 1 1 15.2 0v2.8"/>
    <path d="M4.4 13h2.2v5H5.6a1.2 1.2 0 0 1-1.2-1.2zM19.6 13h-2.2v5h1a1.2 1.2 0 0 0 1.2-1.2z"/>
    <path d="M17.4 18v.8a2.4 2.4 0 0 1-2.4 2.4h-2"/></svg>
  """

  # Rückrufe — a microphone, because what arrives is a recording.
  mic: """
    <svg #{W}><rect x="9.2" y="2.8" width="5.6" height="11" rx="2.8"/>
    <path d="M5.6 11.4a6.4 6.4 0 0 0 12.8 0M12 17.8V21"/></svg>
  """

  # Faxe — a sheet coming out of the machine.
  fax: """
    <svg #{W}><path d="M7 3.4h10v4.2H7z"/><rect x="3.4" y="7.6" width="17.2" height="8.4" rx="1.6"/>
    <path d="M7 16v4.6h10V16"/><path d="M6.4 11h2"/></svg>
  """
