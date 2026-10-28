import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "eh0.headphones"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("eh0.headphones") : null
  readonly property var currentState: service && service.currentState ? service.currentState : ({ connected: false })
  readonly property bool isConnected: currentState.connected === true
  readonly property var lowestPct: service ? service.lowestPct : null
  readonly property bool isLow: service ? service.isLowBattery : false

  readonly property bool showBatteryText: Model.coerceBool(setting("showBattery", true), true)
  readonly property bool hideWhenDisconnected: Model.coerceBool(setting("hideWhenDisconnected", true), true)

  readonly property string glyph: currentState.form === "earbuds" ? "󰥰" : "󰋋"

  readonly property string displayText: {
    if (!isConnected) return glyph
    var parts = [glyph]
    if (isLow) parts.push("!")
    if (showBatteryText && lowestPct !== null && lowestPct !== undefined) {
      parts.push(lowestPct + "%")
    }
    return parts.join(" ")
  }

  readonly property color glyphColor: {
    if (!bar) return "white"
    if (!isConnected || currentState.notSetUp || currentState.connecting) {
      return Qt.darker(bar.foreground, 1.45)
    }
    if (isLow) return bar.urgent
    return bar.foreground
  }

  // ---- Panel popup contract for shell.summon/hide/toggle routing
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function syncSettingsToService() {
    if (service) service.applySettings(root.settings)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  visible: isConnected || !hideWhenDisconnected || opened
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  onBarChanged: {
    syncSettingsToService()
    injectPanel()
  }
  onSettingsChanged: {
    syncSettingsToService()
    injectPanel()
  }
  Component.onCompleted: {
    syncSettingsToService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "eh0.headphones"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function debugState(name: string): void {
      if (root.service) {
        root.service.debugOverrideState = null
        root.service.debugStateName = String(name || "").trim()
      }
    }
    function setMode(mode: string): void {
      if (root.service) root.service.setMode(mode)
    }
    function cycleMode(): void {
      if (root.service) root.service.cycleMode(1)
    }
    function toggleFeature(key: string): void {
      if (root.service) root.service.toggleFeature(key)
    }
    function setCodec(profile: string): void {
      if (root.service) root.service.setCodec(profile)
    }
    function setLatencyMode(mode: string): void {
      if (root.service) root.service.setLatencyMode(mode)
    }
    function setEqPreset(preset: string): void {
      if (root.service) root.service.setEqPreset(preset)
    }
    function setClearBass(val: string): void {
      if (root.service) root.service.setClearBass(parseInt(val, 10))
    }
    function setEqBand(idx: string, val: string): void {
      if (root.service) root.service.setEqBand(parseInt(idx, 10), parseInt(val, 10))
    }
    function setTab(tab: string): void {
      if (panelLoader.item && "activeTab" in panelLoader.item) {
        panelLoader.item.activeTab = String(tab || "control").trim().toLowerCase()
      }
    }
    function toggleMic(): void {
      if (root.service) root.service.toggleMic()
    }
    function toggleMute(): void {
      if (root.service) root.service.toggleOutputMute()
    }
    function setVolume(pct: string): void {
      if (root.service) {
        var n = parseFloat(pct)
        if (n > 1.0) n = n / 100.0
        root.service.setOutputVolume(n)
      }
    }
    function status(): string {
      return JSON.stringify(root.currentState)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.glyph : root.displayText
    labelVisible: true
    hasVisualContent: true
    foreground: root.glyphColor
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.service) root.service.cycleMode(1)
      } else {
        root.togglePanel()
      }
    }
  }
}
