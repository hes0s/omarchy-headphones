import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "Model.js" as Model

Item {
  id: root

  property var shell: null

  // ---- Normalized settings (pushed by BarWidget / Panel)
  property bool showBattery: true
  property bool hideWhenDisconnected: true
  property int lowThreshold: 15
  property bool notifyLow: true
  property string earBehavior: "One out"
  property string lastSettingsJson: ""

  function applySettings(raw) {
    var norm = Model.normalizeSettings(raw)
    var ser = JSON.stringify(norm)
    if (ser === lastSettingsJson) return
    lastSettingsJson = ser
    showBattery = norm.showBattery
    hideWhenDisconnected = norm.hideWhenDisconnected
    lowThreshold = norm.lowThreshold
    notifyLow = norm.notifyLow
    earBehavior = norm.earBehavior
  }

  // ---- Debug override state for deterministic verification & screenshot testing
  property string debugStateName: ""
  property var debugOverrideState: null
  onDebugStateNameChanged: debugOverrideState = null
  readonly property var debugFixtureData: debugOverrideState ? debugOverrideState : (debugStateName !== "" ? Model.debugFixture(debugStateName) : null)

  // ---- Live BlueZ & PipeWire discovery
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  // Cache of parsed `bluetoothctl info <MAC>` per address
  property var infoCache: ({})
  property string probingAddress: ""
  property var probeLines: []
  property bool bridgeBackingOff: false
  property var unsupportedAddresses: ({})
  property var pendingBridgeWrites: []

  // Audio Codec and Latency state
  property var availableCodecs: []
  property string activeCodecProfile: ""
  property string cardName: ""
  property string latencyMode: "balanced"
  property var pactlLines: []

  // PipeWire Audio Output & Input controls
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property var activeAudioSink: {
    if (activeAddress !== "" && pwNodes.length > 0) {
      var normAddr = activeAddress.toLowerCase().replace(/[^0-9a-f]/g, "")
      for (var i = 0; i < pwNodes.length; i++) {
        var n = pwNodes[i]
        if (!n || !n.isSink || n.isStream) continue
        var props = n.ready && n.properties ? n.properties : {}
        var devAddr = String(props["api.bluez5.address"] || props["bluez5.address"] || "").toLowerCase().replace(/[^0-9a-f]/g, "")
        if (normAddr !== "" && devAddr === normAddr && n.audio) return n
      }
    }
    return defaultSink
  }

  readonly property var activeAudioSource: defaultSource

  PwObjectTracker {
    objects: {
      var list = []
      if (root.activeAudioSink) list.push(root.activeAudioSink)
      if (root.activeAudioSource) list.push(root.activeAudioSource)
      return list
    }
  }

  property real debugVolume: 0.75
  property bool debugOutputMuted: false
  property bool debugMicMuted: false

  readonly property real outputVolume: {
    if (debugStateName !== "") return debugVolume
    return activeAudioSink && activeAudioSink.audio ? activeAudioSink.audio.volume : 0.5
  }

  readonly property bool outputMuted: {
    if (debugStateName !== "") return debugOutputMuted
    return activeAudioSink && activeAudioSink.audio ? activeAudioSink.audio.muted : false
  }

  readonly property real inputVolume: {
    return activeAudioSource && activeAudioSource.audio ? activeAudioSource.audio.volume : 1.0
  }

  readonly property bool micMuted: {
    if (debugStateName !== "") return debugMicMuted
    return activeAudioSource && activeAudioSource.audio ? activeAudioSource.audio.muted : false
  }

  function toggleOutputMute() {
    if (debugStateName !== "") {
      debugOutputMuted = !debugOutputMuted
      return
    }
    if (activeAudioSink && activeAudioSink.audio) {
      activeAudioSink.audio.muted = !activeAudioSink.audio.muted
    }
  }

  function toggleMic() {
    if (debugStateName !== "") {
      debugMicMuted = !debugMicMuted
      return
    }
    if (activeAudioSource && activeAudioSource.audio) {
      activeAudioSource.audio.muted = !activeAudioSource.audio.muted
    }
  }

  function setOutputVolume(val) {
    var clamped = Math.max(0, Math.min(1.0, val))
    if (debugStateName !== "") {
      debugVolume = clamped
      if (debugOutputMuted && clamped > 0) debugOutputMuted = false
      return
    }
    if (activeAudioSink && activeAudioSink.audio) {
      activeAudioSink.audio.volume = clamped
      if (activeAudioSink.audio.muted && clamped > 0) {
        activeAudioSink.audio.muted = false
      }
    }
  }

  function adjustOutputVolume(delta) {
    setOutputVolume(outputVolume + delta)
  }

  onPwNodesChanged: {
    startPactlProbe()
  }

  // Find the primary connected audio device (touching all device properties for QML reactivity)
  readonly property var connectedDeviceObj: {
    var list = Model.toArray(btDevices)
    var found = null
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (!d) continue
      var isConn = d.connected === true
      var addr = Model.normalizeMac(d.address)
      var _touch = String(d.name || "") + String(d.deviceName || "") + String(d.batteryAvailable) + String(d.battery)
      if (!isConn || found) continue
      if (Model.isAudioDevice(d, infoCache[addr])) found = d
    }
    return found
  }

  readonly property string activeAddress: connectedDeviceObj ? Model.normalizeMac(connectedDeviceObj.address) : ""
  readonly property string activeName: connectedDeviceObj ? Model.deviceLabel(connectedDeviceObj) : ""
  readonly property int bluezBattery: connectedDeviceObj ? Model.bluezBatteryPercent(connectedDeviceObj) : -1
  readonly property string activeCodec: connectedDeviceObj
    ? Model.extractCodecFromNodes(pwNodes, activeAddress, activeName)
    : "AAC"
  readonly property var activeDriver: Model.detectDriver(infoCache[activeAddress] || {}, activeName)

  function ensureActiveReady() {
    if (activeAddress === "") return
    if (infoCache[activeAddress] === undefined) {
      startInfoProbe(activeAddress)
    }
  }

  // Trigger `bluetoothctl info <MAC>` once when a new connected device appears
  onActiveAddressChanged: {
    bridgeState = null
    bridgeBackingOff = false
    retryTimer.stop()
    ensureActiveReady()
    startPactlProbe()
  }

  Component.onCompleted: {
    ensureActiveReady()
    startPactlProbe()
  }

  function startInfoProbe(addr) {
    if (!Model.isValidMac(addr) || infoProcess.running) return
    probingAddress = addr
    probeLines = []
    infoProcess.command = ["/usr/bin/bluetoothctl", "info", addr]
    infoProcess.running = true
    infoWatchdog.restart()
  }

  Timer {
    id: infoWatchdog
    interval: 4000
    repeat: false
    onTriggered: {
      if (infoProcess.running) infoProcess.running = false
    }
  }

  Process {
    id: infoProcess
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root.probeLines.length < 120) {
          root.probeLines.push(String(line || "").slice(0, 256))
        }
      }
    }
    onExited: function() {
      infoWatchdog.stop()
      var addr = root.probingAddress
      if (addr !== "") {
        var parsed = Model.parseBluetoothctlInfo(root.probeLines.join("\n"))
        var next = ({})
        for (var k in root.infoCache) next[k] = root.infoCache[k]
        next[addr] = parsed
        root.infoCache = next
      }
      root.probingAddress = ""
      if (root.activeAddress !== "" && root.infoCache[root.activeAddress] === undefined) {
        root.startInfoProbe(root.activeAddress)
      }
    }
  }

  function startPactlProbe() {
    if (activeAddress === "" || pactlProcess.running) return
    pactlLines = []
    pactlProcess.command = ["pactl", "-f", "json", "list", "cards"]
    pactlProcess.running = true
  }

  Process {
    id: pactlProcess
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pactlLines.length < 500) {
          root.pactlLines.push(String(line || ""))
        }
      }
    }
    onExited: function() {
      var fullText = root.pactlLines.join("\n")
      root.pactlLines = []
      var res = Model.parseAudioCards(fullText, root.activeAddress)
      if (res) {
        root.availableCodecs = res.codecs
        root.activeCodecProfile = res.activeProfile
        root.cardName = res.cardName
      }
    }
  }

  Timer {
    id: pactlRefreshTimer
    interval: 800
    repeat: false
    onTriggered: {
      root.startPactlProbe()
    }
  }

  Process {
    id: codecSwitchProcess
    running: false
  }

  Process {
    id: latencyProcess
    running: false
  }

  // ---- Vendor Bridge Process (Sony MDR / Apple AirPods AAP)
  readonly property string bridgePath: Qt.resolvedUrl("bin/headphone-bridge").toString().replace(/^file:\/\//, "")
  property var bridgeState: null

  readonly property var bridgeCommand: {
    if (activeAddress === "" || activeDriver.driver === "generic") return ["true"]
    var cmd = [
      "/usr/bin/python3", "-I",
      bridgePath,
      "--driver", activeDriver.driver,
      "--address", activeAddress,
      "--name", activeName
    ]
    if (activeDriver.uuid) {
      cmd.push("--uuid", activeDriver.uuid)
    }
    return cmd
  }

  readonly property bool bridgeWanted: activeAddress !== ""
    && connectedDeviceObj !== null
    && infoCache[activeAddress] !== undefined
    && activeDriver.driver !== "generic"
    && !unsupportedAddresses[activeAddress]
    && !bridgeBackingOff
    && debugStateName === ""

  property bool bridgeArmed: false
  onBridgeWantedChanged: {
    if (!bridgeWanted) {
      bridgeArmed = false
      return
    }
    Qt.callLater(function() {
      root.bridgeArmed = root.bridgeWanted
    })
  }

  function sendBridgeLine(line) {
    if (bridgeProcess.running) {
      bridgeProcess.write(line)
      return
    }
    if (pendingBridgeWrites.length < 8) {
      var nextQ = pendingBridgeWrites.slice()
      nextQ.push(line)
      pendingBridgeWrites = nextQ
    }
    if (bridgeBackingOff) {
      retryTimer.stop()
      bridgeBackingOff = false
    } else {
      ensureActiveReady()
    }
  }

  Process {
    id: bridgeProcess
    running: root.bridgeArmed
    command: root.bridgeCommand
    stdinEnabled: true
    onRunningChanged: {
      if (running && root.pendingBridgeWrites.length > 0) {
        var queued = root.pendingBridgeWrites.slice()
        root.pendingBridgeWrites = []
        for (var i = 0; i < queued.length; i++) {
          bridgeProcess.write(queued[i])
        }
      }
    }
    stdout: SplitParser {
      onRead: function(line) {
        var safeLine = String(line || "").slice(0, 4096)
        var prev = root.bridgeState || {}
        var prevWorn = prev.worn
        var prevEar = prev.ear
        var next = Model.mergeBridgeLine(prev, safeLine, root.bluezBattery >= 0 ? root.bluezBattery : null)
        root.bridgeState = next
        root.checkEarAutoPause(prevWorn, next.worn, prevEar, next.ear)
        root.checkLowBatteryAlerts(next)
      }
    }
    onExited: function(exitCode) {
      root.bridgeArmed = false
      if (exitCode === 3 && root.activeAddress !== "") {
        var nextU = ({})
        for (var k in root.unsupportedAddresses) nextU[k] = root.unsupportedAddresses[k]
        nextU[root.activeAddress] = true
        root.unsupportedAddresses = nextU
        return
      }
      if (root.activeAddress !== "" && root.debugStateName === "") {
        root.bridgeBackingOff = true
        retryTimer.restart()
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    repeat: false
    onTriggered: {
      root.bridgeBackingOff = false
    }
  }

  // ---- Effective State (combines debugFixture, bridgeState, or BlueZ fallback)
  readonly property var currentState: {
    if (debugFixtureData) return debugFixtureData
    if (!connectedDeviceObj) {
      return {
        connected: false,
        address: "",
        name: "",
        brand: "",
        form: "overear",
        codec: "",
        driver: "none",
        driverLabel: "DISCONNECTED",
        battery: { single: null, perBud: false },
        charging: {},
        modes: [],
        mode: "",
        level: null,
        codecs: [],
        activeProfile: "",
        latencyMode: "balanced",
        eq: { available: false, preset: "off", clearBass: 0, bands: [0, 0, 0, 0, 0] },
        outputVolume: root.outputVolume,
        outputMuted: root.outputMuted,
        micMuted: root.micMuted,
        toggles: []
      }
    }
    var info = infoCache[activeAddress] || {}
    var drv = Model.detectDriver(info, activeName)
    var bzBat = bluezBattery >= 0 ? bluezBattery : null
    if (bridgeState) {
      var merged = ({})
      for (var k in bridgeState) merged[k] = bridgeState[k]
      merged.codec = activeCodec
      merged.codecs = root.availableCodecs
      merged.activeProfile = root.activeCodecProfile
      merged.latencyMode = root.latencyMode
      merged.eq = Model.normalizeEq(merged.eq, drv.driver)
      merged.outputVolume = root.outputVolume
      merged.outputMuted = root.outputMuted
      merged.micMuted = root.micMuted
      if (merged.battery && merged.battery.single === null && !merged.battery.perBud && bzBat !== null) {
        merged.battery = {
          single: bzBat,
          left: merged.battery.left,
          right: merged.battery.right,
          case: merged.battery.case,
          perBud: false,
          hasCase: false
        }
      }
      var hasPauseToggle = false
      var tList = (merged.toggles || []).slice()
      for (var t = 0; t < tList.length; t++) {
        if (tList[t].key === "pauseOnEar") hasPauseToggle = true
        if (tList[t].key === "voice" && merged.mode !== "ambient") {
          tList[t] = {
            key: "voice",
            label: "Focus on voice (ambient only)",
            value: false
          }
        }
      }
      if (!hasPauseToggle && (drv.driver === "sony" || drv.driver === "airpods" || drv.driver === "gfps")) {
        tList.push({
          key: "pauseOnEar",
          label: drv.form === "earbuds" ? "Pause when a pod comes out" : "Pause when taken off",
          value: root.earBehavior !== "Never"
        })
      }
      merged.toggles = tList
      return merged
    }
    var isConnecting = drv.driver !== "generic" && (infoProcess.running || bridgeArmed) && bzBat === null
    return {
      connected: true,
      connecting: isConnecting,
      busy: false,
      notSetUp: false,
      address: activeAddress,
      name: activeName || "Headphones",
      brand: drv.brand,
      form: drv.form,
      codec: activeCodec,
      driver: drv.driver,
      driverLabel: isConnecting ? "CONNECTING" : drv.driverLabel,
      battery: { single: bzBat, left: null, right: null, case: null, perBud: false, hasCase: false },
      charging: { single: false },
      modes: drv.driver === "sony" ? ["off", "anc", "ambient"] : (drv.driver === "airpods" ? ["off", "transparency", "adaptive", "anc"] : []),
      mode: "",
      level: null,
      codecs: root.availableCodecs,
      activeProfile: root.activeCodecProfile,
      latencyMode: root.latencyMode,
      eq: Model.normalizeEq(null, drv.driver),
      outputVolume: root.outputVolume,
      outputMuted: root.outputMuted,
      micMuted: root.micMuted,
      toggles: []
    }
  }

  readonly property var cells: Model.buildCells(currentState)
  readonly property var lowestPct: Model.lowestBattery(currentState.battery)
  readonly property bool isLowBattery: lowestPct !== null && lowestPct < lowThreshold

  // ---- Commands from UI to Driver or Settings
  function setMode(modeKey) {
    var m = String(modeKey || "").trim().toLowerCase()
    if (!Model.MODE_LABELS[m]) return
    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.mode = m
      if (copy.driver === "sony") {
        copy.level = m === "ambient" ? { key: "level", label: "Ambient level", value: 12, min: 1, max: 20 } : null
      } else if (copy.driver === "airpods") {
        copy.level = m === "adaptive" ? { key: "adaptive", label: "Adaptive noise level", value: 50, min: 0, max: 100 } : null
      }
      debugOverrideState = copy
      return
    }
    if (bridgeState) {
      var nextState = JSON.parse(JSON.stringify(bridgeState))
      nextState.mode = m
      if (nextState.driver === "sony") {
        var prevVal = (bridgeState.level && bridgeState.level.value) ? bridgeState.level.value : 12
        nextState.level = m === "ambient" ? { key: "level", label: "Ambient level", value: prevVal, min: 1, max: 20 } : null
      } else if (nextState.driver === "airpods") {
        var prevAdap = (bridgeState.level && bridgeState.level.value !== undefined) ? bridgeState.level.value : 50
        nextState.level = m === "adaptive" ? { key: "adaptive", label: "Adaptive noise level", value: prevAdap, min: 0, max: 100 } : null
      }
      bridgeState = nextState
    }
    sendBridgeLine("set " + m + "\n")
  }

  function cycleMode(delta) {
    var modes = currentState.modes || []
    if (modes.length === 0) return
    var curIdx = modes.indexOf(currentState.mode)
    if (curIdx < 0) curIdx = 0
    var step = typeof delta === "number" && delta !== 0 ? delta : 1
    var nextIdx = (curIdx + step + modes.length) % modes.length
    setMode(modes[nextIdx])
  }

  function setLevel(val) {
    var lvlObj = currentState.level
    if (!lvlObj) return
    var clamped = Model.clampInt(val, lvlObj.min || 0, lvlObj.max || 100, lvlObj.value || 10)
    if (bridgeState && bridgeState.level) {
      var nextState = JSON.parse(JSON.stringify(bridgeState))
      nextState.level.value = clamped
      bridgeState = nextState
    }
    sendBridgeLine(lvlObj.key + " " + clamped + "\n")
  }

  function toggleFeature(key) {
    var tList = currentState.toggles || []
    for (var i = 0; i < tList.length; i++) {
      if (tList[i].key === key) {
        var nextVal = !tList[i].value
        if (key === "pauseOnEar") {
          earBehavior = nextVal ? "One out" : "Never"
        }
        if (key === "voice" && nextVal && currentState.mode !== "ambient") {
          setMode("ambient")
        }
        if (bridgeState && Array.isArray(bridgeState.toggles)) {
          var nextState = JSON.parse(JSON.stringify(bridgeState))
          for (var j = 0; j < nextState.toggles.length; j++) {
            if (nextState.toggles[j].key === key) nextState.toggles[j].value = nextVal
          }
          bridgeState = nextState
        }
        sendBridgeLine(key + " " + (nextVal ? "on" : "off") + "\n")
        return
      }
    }
  }

  function setCodec(profileKey) {
    if (!profileKey) return
    if (activeCodecProfile === profileKey) return
    activeCodecProfile = profileKey
    var baseCodecs = (currentState && Array.isArray(currentState.codecs) && currentState.codecs.length > 0)
      ? currentState.codecs
      : availableCodecs
    var nextCodecs = []
    for (var i = 0; i < baseCodecs.length; i++) {
      var c = baseCodecs[i]
      nextCodecs.push({
        profile: c.profile,
        label: c.label,
        hiRes: c.hiRes,
        isMic: c.isMic,
        priority: c.priority,
        active: c.profile === profileKey
      })
    }
    availableCodecs = nextCodecs

    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.activeProfile = profileKey
      copy.codecs = nextCodecs
      for (var j = 0; j < nextCodecs.length; j++) {
        if (nextCodecs[j].active) copy.codec = nextCodecs[j].label
      }
      debugOverrideState = copy
      return
    }

    if (cardName !== "") {
      codecSwitchProcess.command = ["pactl", "set-card-profile", cardName, profileKey]
      codecSwitchProcess.running = true
      pactlRefreshTimer.restart()
    }
  }

  function setLatencyMode(modeKey) {
    var m = String(modeKey || "balanced").toLowerCase()
    var quantum = 0
    if (m === "low") quantum = 256
    else if (m === "hifi") quantum = 2048
    else m = "balanced"

    latencyMode = m
    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.latencyMode = m
      debugOverrideState = copy
      return
    }

    latencyProcess.command = ["pw-metadata", "-n", "settings", "0", "clock.force-quantum", String(quantum)]
    latencyProcess.running = true
  }

  function setEqPreset(presetKey) {
    var p = String(presetKey || "off").trim().toLowerCase()
    var baseEq = Model.normalizeEq(currentState.eq, currentState.driver)
    var nextEq = {
      available: true,
      preset: p,
      clearBass: baseEq.clearBass,
      bands: baseEq.bands.slice()
    }
    if (Model.EQ_CURVES[p]) {
      var curve = Model.EQ_CURVES[p]
      nextEq.clearBass = curve[0]
      nextEq.bands = curve.slice(1, 6)
    }
    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.eq = nextEq
      debugOverrideState = copy
      return
    }
    if (bridgeState) {
      var nextState = JSON.parse(JSON.stringify(bridgeState))
      nextState.eq = nextEq
      bridgeState = nextState
    }
    sendBridgeLine("eqpreset " + p + "\n")
  }

  function setClearBass(val) {
    var cb = Model.clampInt(val, -10, 10, 0)
    var baseEq = Model.normalizeEq(currentState.eq, currentState.driver)
    var nextEq = {
      available: true,
      preset: "manual",
      clearBass: cb,
      bands: baseEq.bands.slice()
    }
    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.eq = nextEq
      debugOverrideState = copy
      return
    }
    if (bridgeState) {
      var nextState = JSON.parse(JSON.stringify(bridgeState))
      nextState.eq = nextEq
      bridgeState = nextState
    }
    sendBridgeLine("clearbass " + cb + "\n")
  }

  function setEqBand(bandIdx, val) {
    var idx = Model.clampInt(bandIdx, 0, 4, 0)
    var bVal = Model.clampInt(val, -10, 10, 0)
    var baseEq = Model.normalizeEq(currentState.eq, currentState.driver)
    var nextBands = baseEq.bands.slice()
    nextBands[idx] = bVal
    var nextEq = {
      available: true,
      preset: "manual",
      clearBass: baseEq.clearBass,
      bands: nextBands
    }
    if (debugStateName !== "") {
      var copy = JSON.parse(JSON.stringify(currentState))
      copy.eq = nextEq
      debugOverrideState = copy
      return
    }
    if (bridgeState) {
      var nextState = JSON.parse(JSON.stringify(bridgeState))
      nextState.eq = nextEq
      bridgeState = nextState
    }
    sendBridgeLine("eqband " + idx + " " + bVal + "\n")
  }

  function resetEq() {
    setEqPreset("off")
  }

  function retryConnection() {
    retryTimer.stop()
    bridgeBackingOff = false
    if (activeAddress !== "") {
      var nextU = ({})
      for (var k in unsupportedAddresses) {
        if (k !== activeAddress) nextU[k] = unsupportedAddresses[k]
      }
      unsupportedAddresses = nextU
      ensureActiveReady()
    }
  }

  // ---- Ear Detection Auto-Pause / Auto-Resume (MPRIS)
  property var pausedPlayers: []

  function checkEarAutoPause(prevWorn, nextWorn, prevEar, nextEar) {
    var action = Model.shouldPauseOnEar(earBehavior, prevWorn, nextWorn, prevEar, nextEar)
    var players = Mpris.players ? Model.toArray(Mpris.players.values) : []
    if (action.pause) {
      var newlyPaused = []
      for (var i = 0; i < players.length; i++) {
        var p = players[i]
        if (p && p.isPlaying && p.canPause) {
          p.pause()
          newlyPaused.push(p)
        }
      }
      if (newlyPaused.length > 0) pausedPlayers = newlyPaused
    } else if (action.resume) {
      for (var j = 0; j < pausedPlayers.length; j++) {
        var rp = pausedPlayers[j]
        if (rp && !rp.isPlaying && rp.canPlay) rp.play()
      }
      pausedPlayers = []
    }
  }

  // ---- Low Battery Notifications (deduplicated per component)
  property var warnedComponents: ({})

  function checkLowBatteryAlerts(state) {
    if (!notifyLow) return
    var res = Model.lowBatteryComponents(state, lowThreshold, warnedComponents)
    warnedComponents = res.warned
    if (res.alerts.length > 0 && !notifyProcess.running) {
      var alert = res.alerts[0]
      notifyProcess.command = [
        "/usr/bin/notify-send",
        "-u", "critical",
        "-a", "Headphones",
        "--",
        Model.cleanText(alert.title, 60),
        Model.cleanText(alert.body, 120)
      ]
      notifyProcess.running = true
    }
  }

  Process {
    id: notifyProcess
    running: false
  }
}
