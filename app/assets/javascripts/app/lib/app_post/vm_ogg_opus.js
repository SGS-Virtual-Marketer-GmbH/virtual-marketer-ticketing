/*
 * VmOggOpus - remux a MediaRecorder WebM/Opus recording into a valid Ogg
 * Opus file, without re-encoding a single sample.
 *
 * Why this exists: WhatsApp's Cloud API only accepts outbound voice notes as
 * audio/ogg (Opus codec), audio/mp4 (AAC), audio/mpeg, audio/amr or
 * audio/aac - never audio/webm. Chrome/Chromium's MediaRecorder cannot
 * produce Ogg directly (MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
 * is false) and its 'audio/mp4' option actually carries an Opus payload, not
 * AAC, so it is unusable for WhatsApp too. Chrome CAN record
 * 'audio/webm;codecs=opus' though, and WebM/Matroska and Ogg are both just
 * containers around the exact same Opus bitstream - so the fix is a plain
 * container remux (copy the compressed Opus packets across, rewrap them),
 * never a decode/re-encode round trip.
 *
 * Deliberately plain, dependency-free JavaScript (not CoffeeScript) so this
 * one file can be pasted into any browser console or loaded standalone in a
 * test harness/Node's `vm` module, with nothing else required.
 *
 * Public API:
 *   window.VmOggOpus.fromWebm(arrayBuffer) -> Uint8Array (a complete .ogg file)
 *
 * References used while writing this: Matroska/EBML element IDs (the
 * matroska-org/matroska-specification project), RFC 7845 (Ogg Opus) and
 * RFC 3533 (the Ogg container) for page/CRC layout, RFC 6716 section 3.1 for
 * the Opus TOC byte / frame-count-from-code-3 logic used to compute granule
 * positions without touching the audio itself.
 */
(function (root) {
  'use strict'

  // ------------------------------------------------------------------ EBML/Matroska element IDs
  // IDs are written here WITH their length-marker bit still set, matching
  // how the Matroska spec itself conventionally names them (e.g. SimpleBlock
  // is universally written as 0xA3, not 0x23) - this is the opposite
  // convention from element *sizes*, where the marker bit is stripped.
  var ID = {
    EBML: 0x1a45dfa3,
    SEGMENT: 0x18538067,
    SEEK_HEAD: 0x114d9b74,
    INFO: 0x1549a966,
    TRACKS: 0x1654ae6b,
    TRACK_ENTRY: 0xae,
    TRACK_NUMBER: 0xd7,
    CODEC_ID: 0x86,
    CODEC_PRIVATE: 0x63a2,
    AUDIO: 0xe1,
    CHANNELS: 0x9f,
    CODEC_DELAY: 0x56aa,
    SEEK_PRE_ROLL: 0x56bb,
    CLUSTER: 0x1f43b675,
    TIMECODE: 0xe7,
    SIMPLE_BLOCK: 0xa3,
    BLOCK_GROUP: 0xa0,
    BLOCK: 0xa1,
    BLOCK_DURATION: 0x9b,
    PREV_SIZE: 0xab,
    POSITION: 0xa7,
    SILENT_TRACKS: 0x5854,
    ENCRYPTED_BLOCK: 0xaf,
    CUES: 0x1c53bb6b,
    TAGS: 0x1254c367,
    CHAPTERS: 0x1043a770,
    ATTACHMENTS: 0x1941a469,
    VOID: 0xec,
    CRC32: 0xbf
  }

  // Elements that may legally appear directly inside an (unknown-size)
  // Segment. Used only to find where an unknown-size Segment/Cluster ends,
  // by scanning forward until an element ID turns up that could not
  // possibly be a child of the container we're inside - see
  // findContainerEnd() below.
  var SEGMENT_CHILD_IDS = makeSet([
    ID.SEEK_HEAD, ID.INFO, ID.TRACKS, ID.CLUSTER, ID.CUES, ID.TAGS,
    ID.CHAPTERS, ID.ATTACHMENTS, ID.VOID, ID.CRC32
  ])
  var CLUSTER_CHILD_IDS = makeSet([
    ID.TIMECODE, ID.SIMPLE_BLOCK, ID.BLOCK_GROUP, ID.PREV_SIZE, ID.POSITION,
    ID.SILENT_TRACKS, ID.ENCRYPTED_BLOCK, ID.VOID, ID.CRC32
  ])

  function makeSet (values) {
    var set = new Set()
    for (var i = 0; i < values.length; i++) set.add(values[i])
    return set
  }

  // ------------------------------------------------------------------ low-level EBML reading

  function vintLength (firstByte) {
    if (firstByte & 0x80) return 1
    if (firstByte & 0x40) return 2
    if (firstByte & 0x20) return 3
    if (firstByte & 0x10) return 4
    if (firstByte & 0x08) return 5
    if (firstByte & 0x04) return 6
    if (firstByte & 0x02) return 7
    if (firstByte & 0x01) return 8
    throw new Error('Invalid WebM file: variable-length integer with a leading 0x00 byte')
  }

  // Element ID: keeps the length-marker bit (see comment on ID above).
  function readId (bytes, offset) {
    if (offset >= bytes.length) throw new Error('Invalid WebM file: unexpected end of data while reading an element ID')
    var length = vintLength(bytes[offset])
    if (offset + length > bytes.length) throw new Error('Invalid WebM file: unexpected end of data while reading an element ID')
    var value = 0
    for (var i = 0; i < length; i++) value = value * 256 + bytes[offset + i]
    return { id: value, length: length }
  }

  // Element size (or any other EBML "vint" data value, e.g. a Block's track
  // number): marker bit stripped. All value bits set to 1 means "unknown
  // size" - Chrome uses this for the Segment and for each in-progress
  // Cluster while it is still recording.
  function readVintValue (bytes, offset) {
    if (offset >= bytes.length) throw new Error('Invalid WebM file: unexpected end of data while reading a variable-length integer')
    var length = vintLength(bytes[offset])
    if (offset + length > bytes.length) throw new Error('Invalid WebM file: unexpected end of data while reading a variable-length integer')
    var valueMask = 0xff >> length
    var isUnknown = (bytes[offset] & valueMask) === valueMask
    var value = bytes[offset] & valueMask
    for (var i = 1; i < length; i++) {
      var b = bytes[offset + i]
      if (b !== 0xff) isUnknown = false
      value = value * 256 + b
    }
    return { value: value, length: length, isUnknown: isUnknown }
  }

  function readElementHeader (bytes, offset) {
    var idInfo = readId(bytes, offset)
    var sizeInfo = readVintValue(bytes, offset + idInfo.length)
    var headerLength = idInfo.length + sizeInfo.length
    var dataStart = offset + headerLength
    var dataEnd = sizeInfo.isUnknown ? Infinity : dataStart + sizeInfo.value
    return { id: idInfo.id, headerLength: headerLength, dataStart: dataStart, dataEnd: dataEnd }
  }

  function readUint (bytes, start, end) {
    var value = 0
    for (var i = start; i < end; i++) value = value * 256 + bytes[i]
    return value
  }

  function readAscii (bytes, start, end) {
    var s = ''
    for (var i = start; i < end; i++) s += String.fromCharCode(bytes[i])
    return s
  }

  // Finds where an unknown-size container actually ends, by scanning
  // forward from `start` and stopping at the first element whose ID is not
  // a legal child of this container (that element belongs to the parent
  // instead, and terminates us). Never consumes that terminating element.
  function findContainerEnd (bytes, start, hardEnd, validChildIds) {
    var pos = start
    while (pos < hardEnd) {
      var el = readElementHeader(bytes, pos)
      if (!validChildIds.has(el.id)) return pos
      if (el.dataEnd === Infinity) {
        throw new Error('Unsupported WebM file: nested element with unknown size (id 0x' + el.id.toString(16) + ')')
      }
      pos = el.dataEnd
    }
    return hardEnd
  }

  // ------------------------------------------------------------------ WebM structure walk

  function parseWebm (bytes) {
    var len = bytes.length

    var header = readElementHeader(bytes, 0)
    if (header.id !== ID.EBML) throw new Error('Not a WebM file: missing EBML header')
    var pos = header.dataEnd === Infinity ? len : header.dataEnd

    header = readElementHeader(bytes, pos)
    if (header.id !== ID.SEGMENT) throw new Error('Not a WebM file: missing Segment element')
    var segmentEnd = header.dataEnd === Infinity ? len : Math.min(header.dataEnd, len)
    pos = header.dataStart

    var track = null
    var clusters = []

    while (pos < segmentEnd) {
      var el = readElementHeader(bytes, pos)

      if (el.id === ID.TRACKS) {
        var tracksEnd = el.dataEnd === Infinity
          ? findContainerEnd(bytes, el.dataStart, segmentEnd, SEGMENT_CHILD_IDS)
          : el.dataEnd
        var found = parseTracks(bytes, el.dataStart, tracksEnd)
        if (found) track = found
        pos = tracksEnd
      } else if (el.id === ID.CLUSTER) {
        var clusterEnd = el.dataEnd === Infinity
          ? findContainerEnd(bytes, el.dataStart, segmentEnd, CLUSTER_CHILD_IDS)
          : el.dataEnd
        clusters.push(parseCluster(bytes, el.dataStart, clusterEnd))
        pos = clusterEnd
      } else {
        if (el.dataEnd === Infinity) {
          throw new Error('Unsupported WebM file: unknown-size element at Segment level (id 0x' + el.id.toString(16) + ')')
        }
        pos = el.dataEnd
      }
    }

    if (!track) throw new Error('No Opus audio track found in this recording')

    return { track: track, clusters: clusters }
  }

  function parseTracks (bytes, start, end) {
    var pos = start
    var opusTrack = null
    while (pos < end) {
      var el = readElementHeader(bytes, pos)
      if (el.dataEnd === Infinity) throw new Error('Unsupported WebM file: unknown-size element inside Tracks')
      if (el.id === ID.TRACK_ENTRY) {
        var entry = parseTrackEntry(bytes, el.dataStart, el.dataEnd)
        if (!opusTrack && entry.codecId === 'A_OPUS') opusTrack = entry
      }
      pos = el.dataEnd
    }
    return opusTrack
  }

  function parseTrackEntry (bytes, start, end) {
    var pos = start
    var entry = { number: null, codecId: null, codecPrivate: null, channels: 1, codecDelay: 0, seekPreRoll: 0 }
    while (pos < end) {
      var el = readElementHeader(bytes, pos)
      if (el.dataEnd === Infinity) throw new Error('Unsupported WebM file: unknown-size element inside TrackEntry')
      switch (el.id) {
        case ID.TRACK_NUMBER:
          entry.number = readUint(bytes, el.dataStart, el.dataEnd)
          break
        case ID.CODEC_ID:
          entry.codecId = readAscii(bytes, el.dataStart, el.dataEnd)
          break
        case ID.CODEC_PRIVATE:
          entry.codecPrivate = bytes.subarray(el.dataStart, el.dataEnd)
          break
        case ID.AUDIO:
          parseAudioSettings(bytes, el.dataStart, el.dataEnd, entry)
          break
        case ID.CODEC_DELAY:
          entry.codecDelay = readUint(bytes, el.dataStart, el.dataEnd)
          break
        case ID.SEEK_PRE_ROLL:
          entry.seekPreRoll = readUint(bytes, el.dataStart, el.dataEnd)
          break
        default:
          break
      }
      pos = el.dataEnd
    }
    return entry
  }

  function parseAudioSettings (bytes, start, end, entry) {
    var pos = start
    while (pos < end) {
      var el = readElementHeader(bytes, pos)
      if (el.dataEnd === Infinity) throw new Error('Unsupported WebM file: unknown-size element inside Audio')
      if (el.id === ID.CHANNELS) entry.channels = readUint(bytes, el.dataStart, el.dataEnd)
      pos = el.dataEnd
    }
  }

  function parseCluster (bytes, start, end) {
    var pos = start
    var blocks = []
    while (pos < end) {
      var el = readElementHeader(bytes, pos)
      if (el.id === ID.SIMPLE_BLOCK) {
        if (el.dataEnd === Infinity) throw new Error('Unsupported WebM file: unknown-size SimpleBlock')
        blocks.push(parseBlockPayload(bytes, el.dataStart, el.dataEnd))
        pos = el.dataEnd
      } else if (el.id === ID.BLOCK_GROUP) {
        var blockGroupEnd = el.dataEnd === Infinity
          ? findContainerEnd(bytes, el.dataStart, end, makeSet([ID.BLOCK, ID.BLOCK_DURATION, ID.VOID, ID.CRC32]))
          : el.dataEnd
        var block = parseBlockGroup(bytes, el.dataStart, blockGroupEnd)
        if (block) blocks.push(block)
        pos = blockGroupEnd
      } else {
        if (el.dataEnd === Infinity) {
          throw new Error('Unsupported WebM file: unknown-size element inside Cluster (id 0x' + el.id.toString(16) + ')')
        }
        pos = el.dataEnd
      }
    }
    return { blocks: blocks }
  }

  function parseBlockGroup (bytes, start, end) {
    var pos = start
    var block = null
    while (pos < end) {
      var el = readElementHeader(bytes, pos)
      if (el.dataEnd === Infinity) throw new Error('Unsupported WebM file: unknown-size element inside BlockGroup')
      if (el.id === ID.BLOCK) block = parseBlockPayload(bytes, el.dataStart, el.dataEnd)
      pos = el.dataEnd
    }
    return block
  }

  // SimpleBlock and Block share the exact same payload structure: a
  // (marker-stripped) vint track number, a 2-byte signed relative
  // timecode, a flags byte, then the frame data. We only support "no
  // lacing" (the two lacing bits in the flags byte both zero) - Chrome
  // never lace-encodes a single-track audio-only recording, and any other
  // producer that does gets a clear, explicit error instead of silently
  // wrong output.
  function parseBlockPayload (bytes, start, end) {
    var trackNumInfo = readVintValue(bytes, start)
    var pos = start + trackNumInfo.length
    if (pos + 3 > end) throw new Error('Invalid WebM file: truncated block')
    var flags = bytes[pos + 2]
    pos += 3
    var lacing = (flags >> 1) & 0x3
    if (lacing !== 0) {
      throw new Error('Unsupported WebM file: laced blocks are not supported (lacing type ' + lacing + ')')
    }
    return { trackNumber: trackNumInfo.value, data: bytes.subarray(pos, end) }
  }

  // ------------------------------------------------------------------ Opus packet duration (RFC 6716 section 3.1)

  // Frame size in milliseconds, indexed by the Opus TOC byte's 5-bit config
  // number (0-31).
  var FRAME_SIZE_MS = [
    10, 20, 40, 60, 10, 20, 40, 60, 10, 20, 40, 60,
    10, 20, 10, 20,
    2.5, 5, 10, 20, 2.5, 5, 10, 20, 2.5, 5, 10, 20, 2.5, 5, 10, 20
  ]
  var FRAME_SIZE_48K = FRAME_SIZE_MS.map(function (ms) { return Math.round(ms * 48) })

  // Number of 48kHz samples represented by one Opus packet, derived purely
  // from its TOC byte (and, for code-3 packets, the frame-count byte that
  // follows it) - never from decoding the audio.
  function opusPacketSamples (packet) {
    if (!packet.length) throw new Error('Invalid Opus packet: empty')
    var toc = packet[0]
    var config = (toc >> 3) & 0x1f
    var code = toc & 0x3
    var frameCount
    if (code === 0) {
      frameCount = 1
    } else if (code === 1 || code === 2) {
      frameCount = 2
    } else {
      if (packet.length < 2) throw new Error('Invalid Opus packet: truncated code-3 packet')
      frameCount = packet[1] & 0x3f
      if (frameCount === 0) throw new Error('Invalid Opus packet: code-3 packet with zero frames')
    }
    return FRAME_SIZE_48K[config] * frameCount
  }

  // ------------------------------------------------------------------ Ogg page building (RFC 3533 / RFC 7845)

  function asciiBytes (str) {
    var out = new Uint8Array(str.length)
    for (var i = 0; i < str.length; i++) out[i] = str.charCodeAt(i) & 0xff
    return out
  }

  function writeUint16LE (bytes, offset, value) {
    bytes[offset] = value & 0xff
    bytes[offset + 1] = (value >> 8) & 0xff
  }

  function writeUint32LE (bytes, offset, value) {
    bytes[offset] = value & 0xff
    bytes[offset + 1] = (value >>> 8) & 0xff
    bytes[offset + 2] = (value >>> 16) & 0xff
    bytes[offset + 3] = (value >>> 24) & 0xff
  }

  // Granule positions here never exceed a few tens of millions (5 minutes
  // at 48kHz is 14.4M), always safely inside the low 32 bits, but the field
  // is a real 64-bit LE integer so we write it as one.
  function writeUint64LE (bytes, offset, value) {
    var low = value % 0x100000000
    var high = Math.floor(value / 0x100000000)
    writeUint32LE(bytes, offset, low)
    writeUint32LE(bytes, offset + 4, high)
  }

  function buildOpusHead (channels, preSkip) {
    var buf = new Uint8Array(19)
    buf.set(asciiBytes('OpusHead'), 0)
    buf[8] = 1 // version
    buf[9] = channels
    writeUint16LE(buf, 10, preSkip)
    writeUint32LE(buf, 12, 48000) // original input sample rate, informational only
    writeUint16LE(buf, 16, 0) // output gain
    buf[18] = 0 // channel mapping family 0 (mono/stereo, no mapping table)
    return buf
  }

  function buildOpusTags () {
    var vendor = asciiBytes('Virtual Marketer')
    var buf = new Uint8Array(8 + 4 + vendor.length + 4)
    buf.set(asciiBytes('OpusTags'), 0)
    writeUint32LE(buf, 8, vendor.length)
    buf.set(vendor, 12)
    writeUint32LE(buf, 12 + vendor.length, 0) // user comment list length = 0
    return buf
  }

  // Ogg's own CRC32: polynomial 0x04C11DB7, NOT reflected, initial value 0,
  // no final XOR, computed with the page's checksum field zeroed. This is
  // deliberately a different algorithm from the common "CRC-32" (zlib/PNG)
  // variant, which is reflected.
  var CRC_TABLE = (function () {
    var table = new Uint32Array(256)
    var poly = 0x04c11db7
    for (var i = 0; i < 256; i++) {
      var crc = i << 24
      for (var j = 0; j < 8; j++) {
        crc = (crc & 0x80000000) ? ((crc << 1) ^ poly) : (crc << 1)
        crc = crc >>> 0
      }
      table[i] = crc >>> 0
    }
    return table
  })()

  function crc32Ogg (bytes) {
    var crc = 0
    for (var i = 0; i < bytes.length; i++) {
      crc = ((crc << 8) ^ CRC_TABLE[((crc >>> 24) ^ bytes[i]) & 0xff]) >>> 0
    }
    return crc >>> 0
  }

  // segments: array of lacing-table byte values (each 0-255).
  // payloadParts: array of Uint8Array slices whose lengths sum, in order,
  // to exactly the same total as `segments`.
  function buildPageFromSegments (segments, payloadParts, serial, pageSequence, granule, headerType) {
    var numSegments = segments.length
    var headerLength = 27 + numSegments
    var payloadLength = 0
    var i
    for (i = 0; i < payloadParts.length; i++) payloadLength += payloadParts[i].length

    var out = new Uint8Array(headerLength + payloadLength)
    out[0] = 0x4f // 'O'
    out[1] = 0x67 // 'g'
    out[2] = 0x67 // 'g'
    out[3] = 0x53 // 'S'
    out[4] = 0 // stream structure version
    out[5] = headerType
    writeUint64LE(out, 6, granule)
    writeUint32LE(out, 14, serial)
    writeUint32LE(out, 18, pageSequence)
    writeUint32LE(out, 22, 0) // checksum, filled in below
    out[26] = numSegments
    for (i = 0; i < numSegments; i++) out[27 + i] = segments[i]

    var pos = headerLength
    for (i = 0; i < payloadParts.length; i++) {
      out.set(payloadParts[i], pos)
      pos += payloadParts[i].length
    }

    var crc = crc32Ogg(out)
    writeUint32LE(out, 22, crc)

    return out
  }

  // The 255-run lacing table for one packet's length: as many 255s as fit,
  // then the remainder - and per spec, a packet whose length is an exact
  // multiple of 255 still gets a trailing 0 segment (otherwise its end
  // would be ambiguous with a longer, still-continuing packet).
  function lacingSegmentsForPacket (length) {
    var segments = []
    var remaining = length
    while (remaining >= 255) {
      segments.push(255)
      remaining -= 255
    }
    segments.push(remaining)
    return segments
  }

  function buildSingleHeaderPage (packetBytes, serial, pageSequence, headerType) {
    var segments = lacingSegmentsForPacket(packetBytes.length)
    var payloadParts = []
    var offset = 0
    for (var i = 0; i < segments.length; i++) {
      payloadParts.push(packetBytes.subarray(offset, offset + segments[i]))
      offset += segments[i]
    }
    return buildPageFromSegments(segments, payloadParts, serial, pageSequence, 0, headerType)
  }

  // Packs a list of raw Opus packets into as few Ogg pages as possible
  // (capped at 255 lacing segments per page), computing each page's
  // granule position as the cumulative 48kHz sample count through the last
  // packet fully completed on that page, and setting the continued-packet
  // flag whenever a single packet's lacing table has to be split across a
  // page boundary. The final page carries the EOS flag.
  function packAudioPages (packets, serial, startPageSequence) {
    var pages = []
    var pageSequence = startPageSequence
    var segments = []
    var payloadParts = []
    var continuationFlag = false
    var cumulativeSamples = 0
    var lastCompletedGranule = 0
    var pageCompletedAnyPacket = false
    var pendingCompletionGranule = 0

    function flush (isEos) {
      var headerType = (continuationFlag ? 0x01 : 0x00) | (isEos ? 0x04 : 0x00)
      var granule = pageCompletedAnyPacket ? pendingCompletionGranule : lastCompletedGranule
      pages.push(buildPageFromSegments(segments, payloadParts, serial, pageSequence, granule, headerType))
      pageSequence++
      segments = []
      payloadParts = []
      continuationFlag = false
      pageCompletedAnyPacket = false
    }

    for (var p = 0; p < packets.length; p++) {
      var packet = packets[p]
      cumulativeSamples += opusPacketSamples(packet)

      var entries = lacingSegmentsForPacket(packet.length)
      var offset = 0
      for (var i = 0; i < entries.length; i++) {
        if (segments.length >= 255) {
          flush(false)
          // If this packet already contributed a segment to the page we
          // just flushed (i > 0), it is genuinely split across the
          // boundary; if not (i === 0), the new page simply starts fresh.
          if (i > 0) continuationFlag = true
        }

        var segLen = entries[i]
        segments.push(segLen)
        payloadParts.push(packet.subarray(offset, offset + segLen))
        offset += segLen

        if (i === entries.length - 1) {
          pageCompletedAnyPacket = true
          pendingCompletionGranule = cumulativeSamples
          lastCompletedGranule = cumulativeSamples
        }
      }
    }

    flush(true)

    return pages
  }

  function randomSerial () {
    return Math.floor(Math.random() * 0x100000000) >>> 0
  }

  // ------------------------------------------------------------------ public API

  function fromWebm (arrayBuffer) {
    var bytes = new Uint8Array(arrayBuffer)
    var parsed = parseWebm(bytes)
    var track = parsed.track

    if (track.codecId !== 'A_OPUS') {
      throw new Error('No Opus audio track found in this recording (codec is ' + track.codecId + ')')
    }

    var opusHead
    if (track.codecPrivate && track.codecPrivate.length >= 19) {
      opusHead = track.codecPrivate
    } else {
      var channels = track.channels || 1
      var preSkip = 312 // recommended default (~6.5ms) when nothing better is known
      if (track.codecDelay) {
        // CodecDelay is in nanoseconds; convert to 48kHz samples.
        preSkip = Math.round(track.codecDelay * 48000 / 1e9)
      }
      opusHead = buildOpusHead(channels, preSkip)
    }

    var packets = []
    for (var c = 0; c < parsed.clusters.length; c++) {
      var blocks = parsed.clusters[c].blocks
      for (var b = 0; b < blocks.length; b++) {
        if (blocks[b].trackNumber === track.number) packets.push(blocks[b].data)
      }
    }
    if (!packets.length) throw new Error('No Opus packets found in this recording')

    var serial = randomSerial()
    var pages = []
    pages.push(buildSingleHeaderPage(opusHead, serial, 0, 0x02)) // BOS
    pages.push(buildSingleHeaderPage(buildOpusTags(), serial, 1, 0x00))
    var audioPages = packAudioPages(packets, serial, 2)
    for (var pg = 0; pg < audioPages.length; pg++) pages.push(audioPages[pg])

    var total = 0
    for (var t = 0; t < pages.length; t++) total += pages[t].length
    var out = new Uint8Array(total)
    var pos = 0
    for (var o = 0; o < pages.length; o++) {
      out.set(pages[o], pos)
      pos += pages[o].length
    }
    return out
  }

  root.VmOggOpus = {
    fromWebm: fromWebm
  }
})(typeof window !== 'undefined' ? window : this)
