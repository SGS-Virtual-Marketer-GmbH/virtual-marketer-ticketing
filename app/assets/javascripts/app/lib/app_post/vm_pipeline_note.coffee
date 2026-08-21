# Reads the internal note the AI pipeline writes when a ticket arrives.
#
# The note is plain text with labelled blocks — "[Datenquellen]", "[Links]",
# "[Antwortvorschlag]" — produced by buildInternalNote() in the pipeline
# (pipeline/processTicket.js). Parsing it here is what lets the workspace show
# the order, the parcel and the drafted reply as cards instead of making
# somebody read a wall of text.
#
# Parsing our own output is a coupling, so it is kept to the block markers and
# nothing else: no guessing at prose, no regex over customer text. A note whose
# format has drifted yields fewer cards, never wrong ones — every getter returns
# null rather than a half-parsed value.
#
# The pipeline's HTML notes arrive with <br> and entities; normalise() undoes
# exactly that and nothing more.

class App.VmPipelineNote
  # Only these headers mean "the pipeline wrote this". Kept in sync with
  # pipelineNote() in the assistant's tools.js.
  @MARKER: ///Virtual\ Marketer\s*[–-]\s*(Klassifikation|Vorab-Erkennung|Verifikation)///

  # The newest pipeline note among a ticket's articles, or null.
  @from: (articles) ->
    for article in (articles or []).slice().reverse()
      continue if !article.internal
      body = App.VmPipelineNote.normalise(article.body)
      return new App.VmPipelineNote(body) if App.VmPipelineNote.MARKER.test(body)
    null

  @normalise: (body) ->
    String(body or '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&amp;/g, '&')

  constructor: (@text) ->

  # Everything under "[Name]" up to the next "[Other]" or the end.
  block: (name) ->
    lines  = @text.split('\n')
    start  = null
    result = []
    for line, i in lines
      if start is null
        start = i if line.trim() is "[#{name}]"
        continue
      break if /^\[[^\]]+\]$/.test(line.trim())
      result.push line
    return null if start is null
    text = result.join('\n').trim()
    if text then text else null

  category: ->
    match = @text.match(/^Kategorie:\s*(.+)$/m)
    if match then match[1].trim() else null

  confidence: ->
    match = @text.match(/^Konfidenz:\s*(\d+)\s*%/m)
    if match then parseInt(match[1], 10) else null

  draft: -> @block('Antwortvorschlag')

  voicemail: -> @block('Voicemail')

  # "[Links]" holds one "Label: https://…" per line, written by the pipeline
  # from the URL the source itself returned — never one we invented.
  links: ->
    block = @block('Links')
    return [] if !block
    result = []
    for line in block.split('\n')
      match = line.match(/^\s*(.+?):\s*(https?:\/\/\S+)\s*$/)
      continue if !match
      result.push(label: match[1].trim(), url: match[2])
    result

  # What the pipeline looked up and what it got, one line per source. Lines that
  # found nothing are kept — "no invoice number in the ticket" is exactly what an
  # agent needs to know before asking the customer for one.
  sources: ->
    block = @block('Datenquellen')
    return [] if !block
    result = []
    for line in block.split('\n')
      # The pipeline writes these as a bulleted list; the dash is decoration.
      trimmed = line.trim().replace(/^[-•]\s*/, '')
      continue if !trimmed
      match = trimmed.match(/^(.+?):\s*(.*)$/)
      continue if !match
      value = match[2].replace(/\s*→\s*https?:\/\/\S+\s*$/, '').trim()
      urlMatch = trimmed.match(/→\s*(https?:\/\/\S+)/)
      result.push(
        label: match[1].trim()
        value: value or null
        url:   if urlMatch then urlMatch[1] else null
        found: !!value and not /keine daten|nicht gefunden|nicht erreichbar|—/i.test(value)
      )
    result
