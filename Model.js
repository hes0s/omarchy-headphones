// Pure model logic for eh0.clock (Headphones plugin).
// Unit-testable under Node.js with zero Quickshell dependencies.

var SONY_UUID_V2 = "956c7b26-d49a-4ba8-b03f-b17d393cb6e2"
var SONY_UUID_V1 = "96cc203e-5068-46ad-b32d-e316f5e069ba"
var GFPS_UUID = "df21fe2c-2515-4fdb-8886-f12c4d67927c"
var AUDIO_SINK_UUID = "0000110b-0000-1000-8000-00805f9b34fb"
var HANDSFREE_UUID = "0000111e-0000-1000-8000-00805f9b34fb"
var HEADSET_UUID = "00001108-0000-1000-8000-00805f9b34fb"

var MODE_LABELS = {
  off: "Off",
  anc: "ANC",
  ambient: "Ambient",
  transparency: "Transp.",
  adaptive: "Adaptive"
}

var MODE_FULL_LABELS = {
  off: "Off",
  anc: "Noise cancelling",
  ambient: "Ambient",
  transparency: "Transparency",
  adaptive: "Adaptive"
}

var LATENCY_MODES = [
  { key: "low", label: "Low (256)", fullName: "Low latency (~5ms)", quantum: 256, icon: "󰓅" },
  { key: "balanced", label: "Balanced", fullName: "Balanced buffer (~21ms)", quantum: 0, icon: "󰾆" },
  { key: "hifi", label: "Hi-Fi (2k)", fullName: "Hi-Fi buffer (~42ms)", quantum: 2048, icon: "󰓃" }
]

var EQ_PRESETS = [
  { key: "off", label: "Flat" },
  { key: "bass", label: "Bass Boost" },
  { key: "vocal", label: "Vocal" },
  { key: "bright", label: "Bright" },
  { key: "excited", label: "Excited" },
  { key: "mellow", label: "Mellow" },
  { key: "treble", label: "Treble" },
  { key: "speech", label: "Speech" },
  { key: "manual", label: "Custom" }
]

var EQ_BAND_LABELS = ["400", "1k", "2.5k", "6.3k", "16k"]

var EQ_CURVES = {
  off:     [0, 0, 0, 0, 0, 0],
  bright:  [0, 0, 1, 2, 4, 6],
  excited: [5, 2, 0, -2, 2, 5],
  mellow:  [1, 0, -1, -2, -4, -5],
  relaxed: [0, 1, -1, -2, -3, -4],
  vocal:   [-2, -2, 2, 4, 3, 0],
  treble:  [0, 0, 0, 2, 5, 7],
  bass:    [7, 4, 1, 0, 0, 0],
  speech:  [-4, -2, 3, 5, 3, -1]
}

function normalizeEq(rawEq, driver) {
  if (!rawEq || typeof rawEq !== "object") {
    if (driver === "sony") {
      return { available: true, preset: "off", clearBass: 0, bands: [0, 0, 0, 0, 0] }
    }
    return { available: false, preset: "off", clearBass: 0, bands: [0, 0, 0, 0, 0] }
  }
  var avail = rawEq.available !== undefined ? !!rawEq.available : (driver === "sony")
  var preset = cleanText(rawEq.preset || "off", 16).toLowerCase()
  if (preset === "custom1" || preset === "custom2") preset = "manual"
  var cb = clampInt(rawEq.clearBass, -10, 10, 0)
  var rawBands = toArray(rawEq.bands)
  var bands = []
  for (var i = 0; i < 5; i++) {
    bands.push(clampInt(rawBands[i], -10, 10, 0))
  }
  return {
    available: avail,
    preset: preset,
    clearBass: cb,
    bands: bands
  }
}

function codecLabelFromProfile(profileKey, description) {
  var desc = String(description || "").toLowerCase()
  var key = String(profileKey || "").toLowerCase()

  if (desc.indexOf("codec ldac") !== -1 || key.indexOf("ldac") !== -1) return "LDAC"
  if (desc.indexOf("codec aptx-hd") !== -1 || desc.indexOf("codec aptx_hd") !== -1 || key.indexOf("aptx_hd") !== -1) return "aptX HD"
  if (desc.indexOf("codec aptx") !== -1 || key.indexOf("aptx") !== -1) return "aptX"
  if (desc.indexOf("codec lc3") !== -1 || key.indexOf("lc3") !== -1) return "LC3"
  if (desc.indexOf("codec opus") !== -1 || key.indexOf("opus") !== -1) return "Opus"
  if (desc.indexOf("codec aac") !== -1 || key.indexOf("aac") !== -1) return "AAC"
  if (desc.indexOf("codec sbc-xq") !== -1 || desc.indexOf("codec sbc_xq") !== -1 || key.indexOf("sbc_xq") !== -1) return "SBC-XQ"
  if (desc.indexOf("codec sbc") !== -1 || key.indexOf("sbc") !== -1) return "SBC"
  if (key === "a2dp-sink") {
    if (desc.indexOf("ldac") !== -1) return "LDAC"
    return "A2DP"
  }
  if (key.indexOf("headset") !== -1) {
    if (desc.indexOf("msbc") !== -1 || key.indexOf("msbc") !== -1) return "mSBC"
    if (desc.indexOf("cvsd") !== -1 || key.indexOf("cvsd") !== -1) return "CVSD"
    return "Headset"
  }
  return cleanText(profileKey, 12)
}

function codecPriority(label) {
  var l = String(label || "").toUpperCase()
  if (l === "LDAC") return 10
  if (l === "APTX HD") return 9
  if (l === "APTX") return 8
  if (l === "LC3") return 7
  if (l === "AAC") return 6
  if (l === "SBC-XQ") return 5
  if (l === "SBC") return 4
  if (l === "OPUS") return 3
  if (l === "MSBC") return 2
  if (l === "CVSD") return 1
  return 0
}

function parseAudioCards(jsonTextOrObj, macAddress) {
  var cards = []
  if (typeof jsonTextOrObj === "string") {
    try {
      cards = JSON.parse(jsonTextOrObj)
    } catch (e) {
      return null
    }
  } else if (Array.isArray(jsonTextOrObj)) {
    cards = jsonTextOrObj
  } else if (jsonTextOrObj && typeof jsonTextOrObj === "object") {
    cards = [jsonTextOrObj]
  }
  if (!Array.isArray(cards)) return null

  var normMac = String(macAddress || "").toLowerCase().replace(/[^0-9a-f]/g, "")
  var targetCard = null
  for (var i = 0; i < cards.length; i++) {
    var c = cards[i]
    if (!c) continue
    var props = c.properties || {}
    var cName = String(c.name || "").toLowerCase()
    var devAddr = String(props["api.bluez5.address"] || props["bluez5.address"] || "").toLowerCase().replace(/[^0-9a-f]/g, "")
    var cNameNorm = cName.replace(/[^0-9a-f]/g, "")
    if (normMac && (devAddr === normMac || cNameNorm.indexOf(normMac) !== -1)) {
      targetCard = c
      break
    }
    if (!targetCard && cName.indexOf("bluez_card") !== -1) {
      targetCard = c
    }
  }
  if (!targetCard) return null

  var activeProf = String(targetCard.active_profile || "")
  var profObj = targetCard.profiles || {}
  var codecList = []
  var seenLabels = {}

  for (var profKey in profObj) {
    if (profKey === "off" || profKey === "pro-audio") continue
    var p = profObj[profKey]
    if (!p || p.available === false) continue
    var label = codecLabelFromProfile(profKey, p.description)
    if (!label) continue
    if (seenLabels[label] && profKey.indexOf("headset") !== -1) continue
    seenLabels[label] = true

    var isHiRes = label === "LDAC" || label.indexOf("aptX") !== -1
    var isMic = profKey.indexOf("headset") !== -1
    codecList.push({
      profile: profKey,
      label: label,
      hiRes: isHiRes,
      isMic: isMic,
      priority: codecPriority(label),
      active: profKey === activeProf
    })
  }

  codecList.sort(function(a, b) {
    return b.priority - a.priority
  })

  var activeLabel = "A2DP"
  for (var j = 0; j < codecList.length; j++) {
    if (codecList[j].active) {
      activeLabel = codecList[j].label
      break
    }
  }

  return {
    cardName: targetCard.name,
    activeProfile: activeProf,
    activeCodec: activeLabel,
    codecs: codecList
  }
}

function cleanText(value, maxLen) {
  var cap = typeof maxLen === "number" && maxLen > 0 ? maxLen : 80
  var raw = String(value === undefined || value === null ? "" : value)
  var stripped = raw
    .replace(/[<>&]/g, "")
    .replace(/[\x00-\x1F\x7F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
  if (stripped.length > cap) return stripped.slice(0, cap)
  return stripped
}

function isValidMac(address) {
  var text = String(address || "").trim()
  return /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(text)
}

function normalizeMac(address) {
  if (!isValidMac(address)) return ""
  return String(address).trim().toUpperCase()
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()
  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []
  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function coerceBool(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  if (typeof value === "string") {
    var lower = value.trim().toLowerCase()
    if (lower === "true" || lower === "1" || lower === "yes" || lower === "on") return true
    if (lower === "false" || lower === "0" || lower === "no" || lower === "off") return false
  }
  return !!fallback
}

function clampInt(value, minVal, maxVal, fallback) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) return fallback
  if (n < minVal) return minVal
  if (n > maxVal) return maxVal
  return n
}

function normalizeSettings(raw) {
  var s = raw || {}
  var ear = String(s.earBehavior || "One out").trim()
  if (ear !== "One out" && ear !== "Both out" && ear !== "Never") ear = "One out"
  return {
    showBattery: coerceBool(s.showBattery, true),
    hideWhenDisconnected: coerceBool(s.hideWhenDisconnected, true),
    lowThreshold: clampInt(s.lowThreshold, 5, 40, 15),
    notifyLow: coerceBool(s.notifyLow, true),
    earBehavior: ear
  }
}

function deviceLabel(device) {
  if (!device) return ""
  var label = cleanText(device.name || device.deviceName || "", 60)
  return label
}

function parseBluetoothctlInfo(output) {
  var text = String(output || "")
  var lines = text.split(/\r?\n/)
  var uuids = []
  var modalias = ""
  var icon = ""
  var name = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    var uuidMatch = line.match(/^UUID:\s+.*?\(([0-9a-fA-F-]{36})\)/)
    if (uuidMatch) {
      var u = uuidMatch[1].toLowerCase()
      if (uuids.indexOf(u) === -1) uuids.push(u)
      continue
    }
    var modMatch = line.match(/^Modalias:\s+(\S+)/i)
    if (modMatch) {
      modalias = modMatch[1].toLowerCase()
      continue
    }
    var iconMatch = line.match(/^Icon:\s+(\S+)/i)
    if (iconMatch) {
      icon = iconMatch[1].toLowerCase()
      continue
    }
    var nameMatch = line.match(/^Name:\s+(.+)$/i)
    if (nameMatch) {
      name = cleanText(nameMatch[1], 60)
    }
  }
  return {
    uuids: uuids,
    modalias: modalias,
    icon: icon,
    name: name
  }
}

function detectDriver(info, fallbackName) {
  var parsed = info || {}
  var uuids = toArray(parsed.uuids).map(function(u) { return String(u).toLowerCase() })
  var modalias = String(parsed.modalias || "").toLowerCase()
  var name = cleanText(parsed.name || fallbackName || "", 60)
  var lowerName = name.toLowerCase()

  if (uuids.indexOf(SONY_UUID_V2) !== -1) {
    return {
      driver: "sony",
      driverLabel: "SONY MDR V2",
      uuid: SONY_UUID_V2,
      form: isEarbudName(lowerName) ? "earbuds" : "overear",
      brand: "Sony"
    }
  }
  if (uuids.indexOf(SONY_UUID_V1) !== -1) {
    return {
      driver: "sony",
      driverLabel: "SONY MDR V1",
      uuid: SONY_UUID_V1,
      form: isEarbudName(lowerName) ? "earbuds" : "overear",
      brand: "Sony"
    }
  }
  if (modalias.indexOf("v004c") !== -1 || lowerName.indexOf("airpods") !== -1 || lowerName.indexOf("beats") !== -1) {
    var isMax = lowerName.indexOf("max") !== -1
    return {
      driver: "airpods",
      driverLabel: "APPLE AAP",
      uuid: "",
      form: isMax ? "overear" : "earbuds",
      brand: "Apple"
    }
  }
  if (lowerName.indexOf("wh-1000xm") !== -1 || lowerName.indexOf("wf-1000xm") !== -1 || lowerName.indexOf("wh-ch") !== -1) {
    var v1 = lowerName.indexOf("xm4") !== -1 || lowerName.indexOf("xm3") !== -1
    return {
      driver: "sony",
      driverLabel: v1 ? "SONY MDR V1" : "SONY MDR V2",
      uuid: v1 ? SONY_UUID_V1 : SONY_UUID_V2,
      form: isEarbudName(lowerName) ? "earbuds" : "overear",
      brand: "Sony"
    }
  }
  if (uuids.indexOf(GFPS_UUID) !== -1 || lowerName.indexOf("pixel buds") !== -1) {
    return {
      driver: "gfps",
      driverLabel: "FAST PAIR",
      uuid: GFPS_UUID,
      form: isEarbudName(lowerName) ? "earbuds" : "overear",
      brand: lowerName.indexOf("pixel") !== -1 ? "Google" : guessBrand(name)
    }
  }
  return {
    driver: "generic",
    driverLabel: "BATTERY ONLY",
    uuid: "",
    form: isEarbudName(lowerName) ? "earbuds" : "overear",
    brand: guessBrand(name)
  }
}

function isEarbudName(lowerName) {
  var s = String(lowerName || "").toLowerCase()
  if (s.indexOf("airpods max") !== -1) return false
  return s.indexOf("airpods") !== -1
    || s.indexOf("wf-") !== -1
    || s.indexOf("buds") !== -1
    || s.indexOf("ear") !== -1
    || s.indexOf("tws") !== -1
    || s.indexOf("pod") !== -1
}

function guessBrand(name) {
  var s = String(name || "").trim()
  if (!s) return "Bluetooth"
  var first = s.split(/\s+/)[0]
  return cleanText(first, 20) || "Bluetooth"
}

function isAudioDevice(device, info) {
  if (!device) return false
  var label = deviceLabel(device).toLowerCase()
  if (!label) return false
  var icon = String((info && info.icon) || device.icon || "").toLowerCase()
  if (icon.indexOf("audio") !== -1 || icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) {
    return true
  }
  var uuids = info && info.uuids ? info.uuids : []
  if (uuids.indexOf(AUDIO_SINK_UUID) !== -1 || uuids.indexOf(HANDSFREE_UUID) !== -1 || uuids.indexOf(HEADSET_UUID) !== -1) {
    return true
  }
  return label.indexOf("wh-") !== -1
    || label.indexOf("wf-") !== -1
    || label.indexOf("airpods") !== -1
    || label.indexOf("bose") !== -1
    || label.indexOf("buds") !== -1
    || label.indexOf("headphone") !== -1
    || label.indexOf("headset") !== -1
    || label.indexOf("jbl") !== -1
    || label.indexOf("soundcore") !== -1
    || label.indexOf("nothing") !== -1
    || label.indexOf("sennheiser") !== -1
    || label.indexOf("momentum") !== -1
}

function bluezBatteryPercent(device) {
  if (!device || !device.batteryAvailable) return null
  var raw = Number(device.battery)
  if (!isFinite(raw) || raw < 0) return null
  var pct = raw <= 1.0 ? Math.round(raw * 100) : Math.round(raw)
  if (pct < 0 || pct > 100) return null
  return pct
}

function validPercent(val) {
  if (val === null || val === undefined) return null
  var n = Number(val)
  if (!isFinite(n)) return null
  var pct = Math.round(n)
  if (pct < 0 || pct > 100) return null
  return pct
}

function extractCodecFromNodes(nodes, address, name) {
  var list = toArray(nodes)
  var normAddr = String(address || "").toLowerCase().replace(/[^0-9a-f]/g, "")
  var lowerName = String(name || "").toLowerCase().trim()
  for (var i = 0; i < list.length; i++) {
    var node = list[i]
    if (!node || !node.isSink || node.isStream) continue
    var props = node.ready && node.properties ? node.properties : {}
    var text = [
      node.name || "",
      node.description || "",
      props["node.name"] || "",
      props["node.description"] || "",
      props["api.bluez5.address"] || "",
      props["bluez5.address"] || ""
    ].join(" ").toLowerCase()
    var textNorm = text.replace(/[^0-9a-f]/g, "")
    var matched = (normAddr !== "" && textNorm.indexOf(normAddr) !== -1)
      || (lowerName !== "" && text.indexOf(lowerName) !== -1)
    if (!matched) continue
    var codec = String(
      props["api.bluez5.codec"]
      || props["bluez5.codec"]
      || props["bluetooth.codec"]
      || ""
    ).trim()
    if (codec) return cleanText(codec.toUpperCase().replace(/_/g, "-"), 16)
    return "A2DP"
  }
  return "BT"
}

function lowestBattery(battery) {
  if (!battery) return null
  var s = validPercent(battery.single)
  if (s !== null) return s
  var candidates = []
  var l = validPercent(battery.left)
  var r = validPercent(battery.right)
  if (l !== null) candidates.push(l)
  if (r !== null) candidates.push(r)
  if (candidates.length === 0) return null
  return Math.min.apply(null, candidates)
}

function buildCells(state) {
  if (!state) return []
  if (state.connecting) {
    return [{ key: "connecting", label: "READING BATTERY", icon: state.form || "overear", value: null, charging: false, placeholder: "…" }]
  }
  var b = state.battery || {}
  var chg = state.charging || {}
  var form = state.form || "overear"
  var hasPerBud = validPercent(b.left) !== null || validPercent(b.right) !== null || b.perBud === true
  if (!hasPerBud) {
    var singleVal = validPercent(b.single)
    return [{
      key: "single",
      label: form === "earbuds" ? "PODS" : "BATTERY",
      icon: form,
      value: singleVal,
      charging: !!chg.single,
      placeholder: singleVal === null ? "No data" : ""
    }]
  }
  var leftVal = validPercent(b.left)
  var rightVal = validPercent(b.right)
  var caseVal = validPercent(b.case)
  var cells = [
    {
      key: "left",
      label: "LEFT",
      icon: "earbuds",
      value: leftVal,
      charging: !!chg.left,
      placeholder: leftVal === null ? "In case" : ""
    },
    {
      key: "right",
      label: "RIGHT",
      icon: "earbuds",
      value: rightVal,
      charging: !!chg.right,
      placeholder: rightVal === null ? "In case" : ""
    }
  ]
  if (b.hasCase !== false) {
    cells.push({
      key: "case",
      label: "CASE",
      icon: "caseIco",
      value: caseVal,
      charging: !!chg.case,
      placeholder: caseVal === null ? "No data" : ""
    })
  }
  return cells
}

function mergeBridgeLine(prev, jsonLine, bluezFallbackBattery) {
  var base = prev || {}
  var parsed = null
  try {
    parsed = typeof jsonLine === "string" ? JSON.parse(jsonLine) : jsonLine
  } catch (e) {
    return base
  }
  if (!parsed || typeof parsed !== "object") return base

  var next = {
    connected: parsed.connected !== undefined ? !!parsed.connected : (base.connected !== false),
    address: cleanText(parsed.address || base.address || "", 20),
    name: cleanText(parsed.name || base.name || "Headphones", 60),
    brand: cleanText(parsed.brand || base.brand || "Bluetooth", 24),
    form: parsed.form || base.form || "overear",
    codec: cleanText(parsed.codec || base.codec || "AAC", 16),
    driver: parsed.driver || base.driver || "generic",
    driverLabel: cleanText(parsed.driverLabel || base.driverLabel || "BATTERY ONLY", 24),
    connecting: !!parsed.connecting,
    busy: !!parsed.busy,
    notSetUp: !!parsed.notSetUp,
    error: cleanText(parsed.error || "", 140),
    battery: {
      single: validPercent(parsed.battery && parsed.battery.single !== undefined ? parsed.battery.single : (base.battery && base.battery.single)),
      left: validPercent(parsed.battery && parsed.battery.left !== undefined ? parsed.battery.left : (base.battery && base.battery.left)),
      right: validPercent(parsed.battery && parsed.battery.right !== undefined ? parsed.battery.right : (base.battery && base.battery.right)),
      case: validPercent(parsed.battery && parsed.battery.case !== undefined ? parsed.battery.case : (base.battery && base.battery.case)),
      perBud: !!(parsed.battery && parsed.battery.perBud),
      hasCase: parsed.battery && parsed.battery.hasCase !== undefined ? !!parsed.battery.hasCase : true
    },
    charging: {
      single: !!(parsed.charging && parsed.charging.single),
      left: !!(parsed.charging && parsed.charging.left),
      right: !!(parsed.charging && parsed.charging.right),
      case: !!(parsed.charging && parsed.charging.case)
    },
    modes: Array.isArray(parsed.modes) ? parsed.modes.filter(function(m) { return !!MODE_LABELS[m] }) : (base.modes || []),
    mode: parsed.mode !== undefined ? String(parsed.mode || "") : (base.mode || ""),
    level: parsed.level !== undefined ? parsed.level : (base.level || null),
    toggles: Array.isArray(parsed.toggles) ? parsed.toggles : (base.toggles || []),
    ear: Array.isArray(parsed.ear) ? parsed.ear : (base.ear || null),
    worn: parsed.worn !== undefined ? parsed.worn : base.worn,
    codecs: Array.isArray(parsed.codecs) ? parsed.codecs : (base.codecs || []),
    activeProfile: parsed.activeProfile || base.activeProfile || "",
    latencyMode: parsed.latencyMode || base.latencyMode || "balanced",
    eq: normalizeEq(parsed.eq !== undefined ? parsed.eq : base.eq, parsed.driver || base.driver || "generic"),
    outputVolume: typeof parsed.outputVolume === "number" ? parsed.outputVolume : (typeof base.outputVolume === "number" ? base.outputVolume : 0.75),
    outputMuted: !!(parsed.outputMuted !== undefined ? parsed.outputMuted : base.outputMuted),
    micMuted: !!(parsed.micMuted !== undefined ? parsed.micMuted : base.micMuted)
  }

  if (next.battery.single === null && !next.battery.perBud && validPercent(bluezFallbackBattery) !== null) {
    next.battery.single = validPercent(bluezFallbackBattery)
  }
  return next
}

function shouldPauseOnEar(earBehavior, prevWorn, nextWorn, prevEar, nextEar) {
  var rule = String(earBehavior || "One out")
  if (rule === "Never") return { pause: false, resume: false }

  if (typeof nextWorn === "boolean" && typeof prevWorn === "boolean" && prevWorn !== nextWorn) {
    return { pause: !nextWorn, resume: nextWorn }
  }

  if (Array.isArray(prevEar) && Array.isArray(nextEar) && prevEar.length >= 2 && nextEar.length >= 2) {
    var prevInCount = (prevEar[0] === "in_ear" ? 1 : 0) + (prevEar[1] === "in_ear" ? 1 : 0)
    var nextInCount = (nextEar[0] === "in_ear" ? 1 : 0) + (nextEar[1] === "in_ear" ? 1 : 0)
    if (rule === "One out") {
      if (prevInCount === 2 && nextInCount < 2) return { pause: true, resume: false }
      if (prevInCount < 2 && nextInCount === 2) return { pause: false, resume: true }
    } else if (rule === "Both out") {
      if (prevInCount > 0 && nextInCount === 0) return { pause: true, resume: false }
      if (prevInCount === 0 && nextInCount > 0) return { pause: false, resume: true }
    }
  }
  return { pause: false, resume: false }
}

function lowBatteryComponents(state, threshold, prevWarned) {
  var warned = {}
  for (var k in (prevWarned || {})) warned[k] = prevWarned[k]
  var alerts = []
  if (!state || !state.connected) return { warned: warned, alerts: alerts }

  var limit = clampInt(threshold, 5, 40, 15)
  var b = state.battery || {}
  var chg = state.charging || {}
  var name = cleanText(state.name || "Headphones", 40)

  function check(key, label, val, isCharging) {
    var pct = validPercent(val)
    if (pct === null) return
    if (pct > limit || isCharging) {
      delete warned[key]
      return
    }
    if (!warned[key]) {
      warned[key] = true
      alerts.push({
        key: key,
        title: label + " is at " + pct + "%",
        body: isCharging ? "Charging now." : "Charge soon to avoid losing audio."
      })
    }
  }

  if (b.perBud) {
    check("left", "Left " + name, b.left, chg.left)
    check("right", "Right " + name, b.right, chg.right)
  } else {
    check("single", name, b.single, chg.single)
  }
  return { warned: warned, alerts: alerts }
}

function debugFixture(stateName) {
  var key = String(stateName || "").trim().toLowerCase()
  var xm4Codecs = [
    { profile: "a2dp-sink", label: "LDAC", hiRes: true, isMic: false, active: true },
    { profile: "a2dp-sink-aac", label: "AAC", hiRes: false, isMic: false, active: false },
    { profile: "a2dp-sink-sbc_xq", label: "SBC-XQ", hiRes: false, isMic: false, active: false },
    { profile: "a2dp-sink-sbc", label: "SBC", hiRes: false, isMic: false, active: false }
  ]
  var twsCodecs = [
    { profile: "a2dp-sink-aac", label: "AAC", hiRes: false, isMic: false, active: true },
    { profile: "a2dp-sink-sbc_xq", label: "SBC-XQ", hiRes: false, isMic: false, active: false },
    { profile: "a2dp-sink-sbc", label: "SBC", hiRes: false, isMic: false, active: false }
  ]

  if (key === "sony-anc" || key === "healthy" || key === "sony") {
    return {
      connected: true, address: "80:99:E7:C5:44:06", name: "WH-1000XM4", brand: "Sony",
      form: "overear", codec: "LDAC", driver: "sony", driverLabel: "SONY MDR V1",
      battery: { single: 80, perBud: false }, charging: { single: false },
      modes: ["off", "anc", "ambient"], mode: "anc", level: null,
      codecs: xm4Codecs, activeProfile: "a2dp-sink", latencyMode: "balanced",
      eq: { available: true, preset: "bass", clearBass: 7, bands: [4, 1, 0, 0, 0] },
      toggles: [
        { key: "voice", label: "Focus on voice", value: false },
        { key: "pauseOnEar", label: "Pause when taken off", value: true }
      ]
    }
  }
  if (key === "sony-ambient" || key === "ambient") {
    return {
      connected: true, address: "80:99:E7:C5:44:06", name: "WH-1000XM4", brand: "Sony",
      form: "overear", codec: "LDAC", driver: "sony", driverLabel: "SONY MDR V1",
      battery: { single: 80, perBud: false }, charging: { single: false },
      modes: ["off", "anc", "ambient"], mode: "ambient",
      level: { key: "level", label: "Ambient level", value: 12, min: 1, max: 20 },
      codecs: xm4Codecs, activeProfile: "a2dp-sink", latencyMode: "balanced",
      eq: { available: true, preset: "vocal", clearBass: -2, bands: [-2, 2, 4, 3, 0] },
      toggles: [
        { key: "voice", label: "Focus on voice", value: true },
        { key: "pauseOnEar", label: "Pause when taken off", value: true }
      ]
    }
  }
  if (key === "airpods" || key === "pods") {
    return {
      connected: true, address: "AA:BB:CC:11:22:33", name: "AirPods Pro 2", brand: "Apple",
      form: "earbuds", codec: "AAC", driver: "airpods", driverLabel: "APPLE AAP",
      battery: { left: 75, right: 80, case: 40, perBud: true, hasCase: true },
      charging: { left: false, right: false, case: true },
      modes: ["off", "transparency", "adaptive", "anc"], mode: "adaptive",
      level: { key: "adaptive", label: "Adaptive noise level", value: 50, min: 0, max: 100 },
      codecs: twsCodecs, activeProfile: "a2dp-sink-aac", latencyMode: "balanced",
      toggles: [
        { key: "ca", label: "Conversation awareness", value: true },
        { key: "onebud", label: "One-bud noise control", value: false },
        { key: "pauseOnEar", label: "Pause when a pod comes out", value: true }
      ]
    }
  }
  if (key === "one-pod" || key === "onepod") {
    return {
      connected: true, address: "AA:BB:CC:11:22:33", name: "AirPods Pro 2", brand: "Apple",
      form: "earbuds", codec: "AAC", driver: "airpods", driverLabel: "APPLE AAP",
      battery: { left: 64, right: null, case: 55, perBud: true, hasCase: true },
      charging: { left: false, right: true, case: false },
      modes: ["off", "transparency", "adaptive", "anc"], mode: "transparency", level: null,
      codecs: twsCodecs, activeProfile: "a2dp-sink-aac", latencyMode: "balanced",
      toggles: [
        { key: "ca", label: "Conversation awareness", value: true },
        { key: "onebud", label: "One-bud noise control", value: false },
        { key: "pauseOnEar", label: "Pause when a pod comes out", value: true }
      ]
    }
  }
  if (key === "low" || key === "low-battery") {
    return {
      connected: true, address: "AA:BB:CC:11:22:33", name: "AirPods Pro 2", brand: "Apple",
      form: "earbuds", codec: "AAC", driver: "airpods", driverLabel: "APPLE AAP",
      battery: { left: 9, right: 14, case: null, perBud: true, hasCase: true },
      charging: { left: false, right: false, case: false },
      modes: ["off", "transparency", "adaptive", "anc"], mode: "anc", level: null,
      codecs: twsCodecs, activeProfile: "a2dp-sink-aac", latencyMode: "low",
      toggles: [
        { key: "ca", label: "Conversation awareness", value: true },
        { key: "onebud", label: "One-bud noise control", value: false },
        { key: "pauseOnEar", label: "Pause when a pod comes out", value: true }
      ]
    }
  }
  if (key === "charging") {
    return {
      connected: true, address: "80:99:E7:C5:44:06", name: "WH-1000XM4", brand: "Sony",
      form: "overear", codec: "LDAC", driver: "sony", driverLabel: "SONY MDR V1",
      battery: { single: 35, perBud: false }, charging: { single: true },
      modes: ["off", "anc", "ambient"], mode: "off", level: null,
      codecs: xm4Codecs, activeProfile: "a2dp-sink", latencyMode: "balanced",
      toggles: [
        { key: "voice", label: "Focus on voice", value: false },
        { key: "pauseOnEar", label: "Pause when taken off", value: true }
      ]
    }
  }
  if (key === "connecting") {
    return {
      connected: true, connecting: true, address: "80:99:E7:C5:44:06", name: "WH-1000XM4",
      brand: "Sony", form: "overear", codec: "LDAC", driver: "sony", driverLabel: "CONNECTING",
      battery: { single: null, perBud: false }, charging: {},
      modes: ["off", "anc", "ambient"], mode: "", level: null, toggles: [],
      codecs: [], activeProfile: "", latencyMode: "balanced"
    }
  }
  if (key === "busy" || key === "failed") {
    return {
      connected: true, busy: true, address: "80:99:E7:C5:44:06", name: "WH-1000XM4",
      brand: "Sony", form: "overear", codec: "LDAC", driver: "sony", driverLabel: "SONY MDR V1",
      battery: { single: 80, perBud: false }, charging: {},
      modes: ["off", "anc", "ambient"], mode: "", level: null, toggles: [],
      codecs: [], activeProfile: "", latencyMode: "balanced"
    }
  }
  if (key === "generic") {
    return {
      connected: true, address: "11:22:33:44:55:66", name: "JBL Tune 510BT",
      brand: "JBL", form: "overear", codec: "SBC-XQ", driver: "generic", driverLabel: "BATTERY ONLY",
      battery: { single: 60, perBud: false }, charging: {}, modes: [], mode: "", level: null, toggles: [],
      codecs: twsCodecs, activeProfile: "a2dp-sink-sbc_xq", latencyMode: "balanced"
    }
  }
  if (key === "gfps" || key === "pixel-buds" || key === "fast-pair") {
    return {
      connected: true, address: "24:28:FD:88:99:AA", name: "Pixel Buds Pro 2",
      brand: "Google", form: "earbuds", codec: "AAC", driver: "gfps", driverLabel: "FAST PAIR",
      battery: { single: null, left: 95, right: 90, case: 80, perBud: true, hasCase: true },
      charging: { single: false, left: false, right: false, case: true },
      modes: [], mode: "", level: null, toggles: [],
      codecs: twsCodecs, activeProfile: "a2dp-sink-aac", latencyMode: "balanced"
    }
  }
  if (key === "notsetup" || key === "not-set-up") {
    return {
      connected: true, notSetUp: true, address: "AA:BB:CC:11:22:33", name: "AirPods Pro 2",
      brand: "Apple", form: "earbuds", codec: "AAC", driver: "airpods", driverLabel: "APPLE AAP",
      battery: { single: 70, perBud: false }, charging: {}, modes: [], mode: "", level: null, toggles: [],
      codecs: [], activeProfile: "", latencyMode: "balanced"
    }
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    SONY_UUID_V1: SONY_UUID_V1,
    SONY_UUID_V2: SONY_UUID_V2,
    GFPS_UUID: GFPS_UUID,
    MODE_LABELS: MODE_LABELS,
    MODE_FULL_LABELS: MODE_FULL_LABELS,
    LATENCY_MODES: LATENCY_MODES,
    EQ_PRESETS: EQ_PRESETS,
    EQ_BAND_LABELS: EQ_BAND_LABELS,
    EQ_CURVES: EQ_CURVES,
    normalizeEq: normalizeEq,
    cleanText: cleanText,
    isValidMac: isValidMac,
    normalizeMac: normalizeMac,
    toArray: toArray,
    coerceBool: coerceBool,
    clampInt: clampInt,
    normalizeSettings: normalizeSettings,
    deviceLabel: deviceLabel,
    parseBluetoothctlInfo: parseBluetoothctlInfo,
    detectDriver: detectDriver,
    isAudioDevice: isAudioDevice,
    bluezBatteryPercent: bluezBatteryPercent,
    validPercent: validPercent,
    extractCodecFromNodes: extractCodecFromNodes,
    lowestBattery: lowestBattery,
    buildCells: buildCells,
    mergeBridgeLine: mergeBridgeLine,
    shouldPauseOnEar: shouldPauseOnEar,
    lowBatteryComponents: lowBatteryComponents,
    codecLabelFromProfile: codecLabelFromProfile,
    parseAudioCards: parseAudioCards,
    debugFixture: debugFixture
  }
}
