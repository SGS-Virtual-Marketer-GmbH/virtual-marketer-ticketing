# Artwork for the "Meine Statistik" dashboard cards (∅ Wartezeit, Stimmung,
# Kanal-Verteilung, Zugewiesen, Tickets in Bearbeitung, Wiedereröffnungsrate).
#
# These cards used to render Zammad's own stock icons straight from the app-wide
# sprite (public/assets/images/icons.svg): a colourful hand-drawn stopwatch, six
# differently-coloured cartoon smiley speech bubbles (one per health state), a
# green/orange "papers" ticket stack, and orange/grey speech-bubble-ish glyphs
# for in-process/reopening. None of that matches the Virtual Marketer brand —
# a minimal line-icon set, vm-red on vm-gray, one weight throughout — and mixing
# six different icon styles on six cards in the same row reads as unfinished.
#
# Only the shapes live here; @VmIcon (view_helpers.coffee) wraps them in the
# actual <svg> tag and applies the class list, mirroring how @Icon renders the
# app-wide sprite so the existing per-widget CSS (.stopwatch-icon etc.) keeps
# working unchanged.
#
# House style, copied from App.VmAgentTileIcons so the whole custom dashboard
# reads as one set:
#   * 24x24 viewBox, no fill, stroke: currentColor, stroke-width 1.6
#   * round caps and joins
#   * one clear silhouette per icon — read at ~20-36px, not studied
#
# Deliberately ONE icon per card regardless of health state (good/ok/bad/...) —
# the number and the coloured detail text already say whether it's good or bad;
# six different mood glyphs swapped in and out was exactly the inconsistency
# being fixed here.

App.VmStatIcons =
  # ∅ Wartezeit heute — a simple clock face, no stopwatch button/crown.
  'waiting-time': """
    <circle cx="12" cy="12.6" r="8.2"/><path d="M12 8v4.6l3 2.2"/><path d="M9.4 2.6h5.2"/>
  """

  # Stimmung — one calm, neutral face. Which health state it actually is comes
  # from the percentage next to it, not from swapping the face.
  mood: """
    <circle cx="12" cy="12" r="8.4"/><path d="M8.6 14.4c1 1.2 2.2 1.8 3.4 1.8s2.4-.6 3.4-1.8"/>
    <path d="M9 9.6v1.4M15 9.6v1.4"/>
  """

  # Tickets in Bearbeitung — a document with one progress line, i.e. "partway
  # through", rather than the old padlock-ish glyph.
  'in-process': """
    <rect x="4.6" y="4.2" width="14.8" height="15.6" rx="2"/><path d="M7.8 9.4h9.2M7.8 13h5.4"/>
  """

  # Zugewiesen — a small stack of tickets. Replaces the old bar-chart-by-icon
  # (one "one-ticket" glyph repeated per percentage point) with a single static
  # icon; the actual count is already in the label underneath.
  assigned: """
    <path d="M5 8.2h11.4a3.4 3.4 0 1 1 0 6.8H8.4" opacity=".55"/>
    <rect x="4.4" y="6.6" width="13.4" height="9.4" rx="1.6"/><path d="M9.6 6.6v9.4" stroke-dasharray="1.6 1.6"/>
  """

  # Wiedereröffnungsrate — a reopen/retry arrow, not a padlock.
  reopening: """
    <path d="M18.8 8.2A7.2 7.2 0 1 0 20 13"/><path d="M19 4.2v4.4h-4.4"/>
  """

  # Kanal-Verteilung row icons — same house style as the mail/phone pictograms
  # everywhere else, instead of the tiny default sprite glyphs.
  email: """
    <rect x="3.6" y="5.8" width="16.8" height="12.4" rx="1.6"/><path d="M4.2 6.6l7.8 6.2 7.8-6.2"/>
  """

  phone: """
    <path d="M8.6 4.6c.8 0 1.8.2 2.1.9l1 2.3c.3.6 0 1.3-.4 1.7l-1.3 1.2c1 2.2 2.6 3.8 4.8 4.8l1.2-1.3c.4-.4 1.1-.7 1.7-.4l2.3 1c.7.3.9 1.3.9 2.1 0 1.6-1.4 2.6-2.9 2.3-5.4-1.1-9.7-5.4-10.8-10.8-.3-1.5.7-2.9 2.3-2.9Z"/>
  """

  web: """
    <circle cx="12" cy="12" r="8.4"/><path d="M3.6 12h16.8"/>
    <path d="M12 3.6a13 13 0 0 1 0 16.8"/><path d="M12 3.6a13 13 0 0 0 0 16.8"/>
  """

  chat: """
    <path d="M4.4 5.8h15.2v9.6h-9l-3.8 3.2v-3.2H4.4z"/>
  """
