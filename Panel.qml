import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eh0.headphones"
  ipcTarget: "eh0.headphones"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("eh0.headphones") : null
  readonly property var st: service && service.currentState ? service.currentState : ({
    connected: false, name: "No headphones connected", codec: "", driverLabel: "DISCONNECTED",
    modes: [], toggles: [], battery: {}, eq: { available: false, preset: "off", clearBass: 0, bands: [0, 0, 0, 0, 0] }
  })
  readonly property var eqState: Model.normalizeEq(st.eq, st.driver)
  readonly property var cells: service ? service.cells : []
  readonly property int lowThreshold: service ? service.lowThreshold : 15

  property string activeTab: "control"

  readonly property var tabsList: [
    { key: "control", icon: "󰋋", label: "Control" },
    { key: "eq", icon: "󰺢", label: "Equalizer" },
    { key: "audio", icon: "󰓃", label: "Audio" },
    { key: "settings", icon: "󰒓", label: "Settings" }
  ]

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dimColor: Qt.darker(fg, 1.55)
  readonly property color lineColor: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property color trackBgColor: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color selBgColor: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string compactBatteryText: {
    if (!st.connected) return "OFFLINE"
    if (st.connecting) return "CONNECTING"
    var b = st.battery || {}
    if (b.perBud) {
      var parts = []
      if (b.left !== null && b.left !== undefined) parts.push("L " + b.left + "%")
      if (b.right !== null && b.right !== undefined) parts.push("R " + b.right + "%")
      if (parts.length > 0) return parts.join(" · ")
    }
    var lowP = service && service.lowestPct !== null && service.lowestPct !== undefined ? service.lowestPct : null
    if (lowP !== null) return lowP + "%"
    return "BT"
  }

  readonly property string compactStatusPillText: {
    if (!st.connected) return "DISCONNECTED"
    var items = [compactBatteryText]
    if (st.codec) items.push(st.codec)
    if (st.mode && Model.MODE_LABELS[st.mode]) items.push(Model.MODE_LABELS[st.mode])
    return Model.cleanText(items.join(" · "), 36)
  }

  component PlainLabel: Text {
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: root.fontFamily
    color: root.fg
  }

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function cycleTab(delta) {
    var keys = ["control", "eq", "audio", "settings"]
    var idx = keys.indexOf(root.activeTab)
    if (idx < 0) idx = 0
    root.activeTab = keys[(idx + delta + keys.length) % keys.length]
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.service) root.service.applySettings(entry)
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleThreshold() {
    var steps = [10, 15, 20, 25, 30]
    var cur = service ? service.lowThreshold : 15
    var idx = steps.indexOf(cur)
    var next = steps[(idx + 1) % steps.length]
    persistSettings({ lowThreshold: next })
  }

  function cycleEarBehavior() {
    var opts = ["One out", "Both out", "Never"]
    var cur = service ? service.earBehavior : "One out"
    var idx = opts.indexOf(cur)
    var next = opts[(idx + 1) % opts.length]
    persistSettings({ earBehavior: next })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(mainCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.service) {
          if (root.activeTab === "control") {
            root.service.cycleMode(dx > 0 ? 1 : -1)
          }
        }
      }
      onCloseRequested: {
        if (root.activeTab !== "control") root.activeTab = "control"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === ",") {
          root.activeTab = (root.activeTab === "settings") ? "control" : "settings"
        } else if (t === "[") {
          root.cycleTab(-1)
        } else if (t === "]") {
          root.cycleTab(1)
        } else if (t === "1") {
          root.activeTab = "control"
        } else if (t === "2") {
          root.activeTab = "eq"
        } else if (t === "3") {
          root.activeTab = "audio"
        } else if (t === "4") {
          root.activeTab = "settings"
        } else if (t === "r" || t === "R") {
          if (root.activeTab === "eq" && root.service) root.service.resetEq()
          else if (root.service) root.service.retryConnection()
        } else if (t === "m" || t === "M") {
          if (root.service) root.service.toggleMic()
        } else if (t === "v" || t === "V") {
          if (root.service) root.service.toggleOutputMute()
        } else if (t === "+" || t === "=") {
          if (root.service) root.service.adjustOutputVolume(0.05)
        } else if (t === "-" || t === "_") {
          if (root.service) root.service.adjustOutputVolume(-0.05)
        }
      }

      Column {
        id: mainCol
        width: parent.width
        spacing: Style.space(10)

        // ====================================================================
        // PERSISTENT TOP HEADER: Device Name + Compact Status/Battery Pill
        // ====================================================================
        Item {
          width: parent.width
          height: Style.space(34)

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            PlainLabel {
              text: Model.cleanText(root.st.connected ? root.st.name : "No headphones connected", 28)
              font.pixelSize: Style.font.title
              font.bold: true
            }

            PlainLabel {
              text: {
                if (!root.st.connected) return "DISCONNECTED"
                if (root.st.connecting) return "CONNECTING"
                if (root.st.busy) return "CONTROLS BUSY"
                return Model.cleanText(root.st.driverLabel || "BLUETOOTH", 28)
              }
              font.pixelSize: 10
              color: root.dimColor
            }
          }

          Rectangle {
            id: statusPill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(26)
            width: pillRow.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: root.trackBgColor
            border.width: 1
            border.color: (root.service && root.service.isLowBattery) ? root.urgentColor : root.lineColor

            Row {
              id: pillRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              PlainLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: root.st.form === "earbuds" ? "󰥰" : "󰋋"
                font.pixelSize: Style.font.bodySmall
                color: (root.service && root.service.isLowBattery) ? root.urgentColor : root.accentColor
              }

              PlainLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: root.compactStatusPillText
                font.pixelSize: Style.font.caption
                font.bold: true
                color: (root.service && root.service.isLowBattery) ? root.urgentColor : root.fg
              }
            }
          }
        }

        // ====================================================================
        // 4-TAB NAVIGATION BAR (Control · Equalizer · Audio · Settings)
        // ====================================================================
        Rectangle {
          id: navTabBar
          width: parent.width
          height: Style.space(32)
          color: "transparent"
          border.width: 1
          border.color: root.lineColor
          radius: Style.cornerRadius

          Row {
            anchors.fill: parent

            Repeater {
              model: root.tabsList

              Item {
                required property var modelData
                required property int index
                readonly property bool active: root.activeTab === modelData.key
                readonly property int count: root.tabsList.length

                width: Math.floor(navTabBar.width / Math.max(1, count))
                height: navTabBar.height

                Rectangle {
                  anchors.fill: parent
                  color: active ? root.selBgColor : (tabMouse.containsMouse ? root.trackBgColor : "transparent")
                }

                Rectangle {
                  visible: active
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: 2
                  color: root.accentColor
                }

                Rectangle {
                  visible: index < count - 1
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 1
                  color: root.lineColor
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(5)

                  PlainLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.icon
                    font.pixelSize: Style.font.bodySmall
                    color: active ? root.accentColor : root.dimColor
                  }

                  PlainLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pixelSize: Style.font.bodySmall
                    font.bold: active
                    color: active ? root.fg : root.dimColor
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    root.activeTab = modelData.key
                  }
                }
              }
            }
          }
        }

        // ====================================================================
        // TAB 1: CONTROL (Battery Cards + Noise Control + Smart Features)
        // ====================================================================
        Column {
          id: controlTabView
          visible: root.activeTab === "control"
          width: parent.width
          spacing: Style.space(10)

          // ---- Disconnected Empty State
          Rectangle {
            visible: !root.st.connected
            width: parent.width
            height: Style.space(82)
            color: "transparent"
            border.width: 1
            border.color: root.lineColor
            radius: Style.cornerRadius

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)

              PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰋋"
                font.pixelSize: Style.font.display
                color: root.dimColor
              }
              PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Connect your headphones in Bluetooth to see battery and controls."
                font.pixelSize: Style.font.bodySmall
                color: root.dimColor
              }
            }
          }

          // ---- Battery Cells Row (1 cell for over-ear, 3 cells for L / R / Case)
          Row {
            id: cellsRow
            visible: root.st.connected && root.cells.length > 0
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: root.cells

              Rectangle {
                required property var modelData
                readonly property bool hasVal: modelData.value !== null && modelData.value !== undefined
                readonly property int pct: hasVal ? Number(modelData.value) : 0
                readonly property bool low: hasVal && pct < root.lowThreshold

                width: Math.floor((cellsRow.width - (root.cells.length - 1) * cellsRow.spacing) / Math.max(1, root.cells.length))
                height: Style.space(98)
                color: "transparent"
                border.width: 1
                border.color: root.lineColor
                radius: Style.cornerRadius
                opacity: hasVal || root.st.connecting ? 1.0 : 0.48

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(5)

                  PlainLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.icon === "caseIco" ? "󰢝" : (modelData.icon === "earbuds" ? "󰥰" : "󰋋")
                    font.pixelSize: Style.font.heading
                    color: root.fg
                  }

                  Item {
                    width: parent.width
                    height: Style.space(24)

                    Row {
                      visible: hasVal
                      anchors.centerIn: parent
                      spacing: Style.space(1)

                      PlainLabel {
                        text: String(pct)
                        font.pixelSize: 21
                        font.bold: true
                        color: low ? root.urgentColor : root.fg
                      }
                      PlainLabel {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(2)
                        text: "%"
                        font.pixelSize: Style.font.bodySmall
                        color: root.dimColor
                      }
                    }

                    PlainLabel {
                      visible: !hasVal
                      anchors.centerIn: parent
                      text: Model.cleanText(modelData.placeholder || "No data", 18)
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                      color: root.dimColor
                    }
                  }

                  PlainLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (modelData.charging ? "⚡ " : "") + Model.cleanText(modelData.label, 18)
                    font.pixelSize: Style.font.caption
                    color: root.dimColor
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(5)
                    radius: 2
                    color: root.trackBgColor

                    Rectangle {
                      visible: hasVal
                      width: Math.max(0, Math.min(parent.width, Math.round(parent.width * (pct / 100.0))))
                      height: parent.height
                      radius: 2
                      color: low ? root.urgentColor : root.fg
                    }
                  }
                }
              }
            }
          }

          // ---- Noise Control Segmented Row
          Column {
            visible: root.st.connected && !root.st.busy && !root.st.notSetUp && (root.st.modes || []).length > 0
            width: parent.width
            spacing: Style.space(6)

            PlainLabel {
              text: "NOISE CONTROL"
              font.pixelSize: Style.font.caption
              color: root.dimColor
            }

            Rectangle {
              id: segBar
              width: parent.width
              height: Style.space(30)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              radius: Style.cornerRadius
              opacity: root.st.connecting ? 0.5 : 1.0

              Row {
                anchors.fill: parent

                Repeater {
                  model: root.st.modes || []

                  Item {
                    required property string modelData
                    required property int index
                    readonly property bool active: !root.st.connecting && root.st.mode === modelData
                    readonly property int count: (root.st.modes || []).length

                    width: Math.floor(segBar.width / Math.max(1, count))
                    height: segBar.height

                    Rectangle {
                      anchors.fill: parent
                      color: active ? root.selBgColor : (segMouse.containsMouse ? root.trackBgColor : "transparent")
                    }

                    Rectangle {
                      visible: active
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: 2
                      color: root.accentColor
                    }

                    Rectangle {
                      visible: index < count - 1
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: 1
                      color: root.lineColor
                    }

                    PlainLabel {
                      anchors.centerIn: parent
                      text: Model.MODE_LABELS[modelData] || modelData
                      font.pixelSize: Style.font.body
                      font.bold: active
                      color: active ? root.fg : root.dimColor
                    }

                    MouseArea {
                      id: segMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: !root.st.connecting
                      onClicked: {
                        if (root.service) root.service.setMode(modelData)
                      }
                    }
                  }
                }
              }
            }

            // ---- Contextual Level Slider (Ambient level 1-20 or Adaptive 0-100)
            Item {
              visible: !root.st.connecting && root.st.level !== null && root.st.level !== undefined
              width: parent.width
              height: Style.space(24)

              Row {
                anchors.fill: parent
                spacing: Style.space(10)

                PlainLabel {
                  id: sliderLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.st.level ? Model.cleanText(root.st.level.label, 24) : ""
                  font.pixelSize: Style.font.caption
                  color: root.dimColor
                }

                Item {
                  id: sliderTrackWrap
                  width: parent.width - sliderLabel.implicitWidth - sliderValLabel.implicitWidth - Style.space(24)
                  height: parent.height

                  Rectangle {
                    id: sliderTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Style.space(6)
                    radius: 3
                    color: root.trackBgColor

                    Rectangle {
                      readonly property real minV: root.st.level ? Number(root.st.level.min || 0) : 0
                      readonly property real maxV: root.st.level ? Number(root.st.level.max || 100) : 100
                      readonly property real curV: root.st.level ? Number(root.st.level.value || 0) : 0
                      readonly property real ratio: maxV > minV ? Math.max(0, Math.min(1, (curV - minV) / (maxV - minV))) : 0
                      width: Math.round(parent.width * ratio)
                      height: parent.height
                      radius: 3
                      color: root.accentColor
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    function applyMouse(mx) {
                      if (!root.st.level || !root.service) return
                      var minV = Number(root.st.level.min || 0)
                      var maxV = Number(root.st.level.max || 100)
                      var ratio = Math.max(0, Math.min(1, mx / Math.max(1, width)))
                      var target = Math.round(minV + ratio * (maxV - minV))
                      root.service.setLevel(target)
                    }
                    onClicked: function(mouse) { applyMouse(mouse.x) }
                    onPositionChanged: function(mouse) {
                      if (pressed) applyMouse(mouse.x)
                    }
                  }
                }

                PlainLabel {
                  id: sliderValLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.st.level ? String(root.st.level.value) : ""
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }
          }

          // ---- Features 2-Column Chip Grid
          Column {
            visible: root.st.connected && !root.st.connecting && !root.st.busy && (root.st.toggles || []).length > 0
            width: parent.width
            spacing: Style.space(6)

            PlainLabel {
              text: "SMART FEATURES"
              font.pixelSize: Style.font.caption
              color: root.dimColor
            }

            Grid {
              id: featureGrid
              width: parent.width
              columns: 2
              spacing: Style.space(6)

              Repeater {
                model: root.st.toggles || []

                Rectangle {
                  required property var modelData
                  readonly property bool isOn: modelData.value === true

                  width: Math.floor((featureGrid.width - featureGrid.spacing) / 2)
                  height: Style.space(40)
                  color: chipMouse.containsMouse ? root.trackBgColor : "transparent"
                  border.width: 1
                  border.color: isOn ? root.fg : root.lineColor
                  radius: Style.cornerRadius

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(9)
                    anchors.rightMargin: Style.space(9)
                    spacing: Style.space(6)

                    PlainLabel {
                      width: parent.width - swBox.width - Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.cleanText(modelData.label, 32)
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      lineHeight: 1.05
                    }

                    Rectangle {
                      id: swBox
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(26)
                      height: Style.space(14)
                      color: "transparent"
                      border.width: 1
                      border.color: isOn ? root.fg : root.dimColor

                      Rectangle {
                        width: Style.space(8)
                        height: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        x: isOn ? parent.width - width - 3 : 3
                        color: isOn ? root.fg : root.dimColor
                      }
                    }
                  }

                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      if (root.service) root.service.toggleFeature(modelData.key)
                    }
                  }
                }
              }
            }
          }

          // ---- Busy / Phone App Holding Channel Box
          Rectangle {
            visible: root.st.connected && root.st.busy === true
            width: parent.width
            height: busyCol.implicitHeight + Style.space(20)
            color: "transparent"
            border.width: 1
            border.color: root.dimColor
            radius: Style.cornerRadius

            Column {
              id: busyCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Another app is holding the noise controls."
                font.pixelSize: Style.font.body
                font.bold: true
              }
              PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Close the companion app on your phone, or turn its Bluetooth off, then try again. Battery keeps updating meanwhile."
                font.pixelSize: Style.font.bodySmall
              }
              PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Only one app at a time can use the " + Model.cleanText(root.st.driverLabel, 24) + " channel."
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }
            }
          }

          // ---- AirPods Not Set Up Box
          Rectangle {
            visible: root.st.connected && root.st.notSetUp === true
            width: parent.width
            height: setupCol.implicitHeight + Style.space(20)
            color: "transparent"
            border.width: 1
            border.color: root.dimColor
            radius: Style.cornerRadius

            Column {
              id: setupCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "AirPods won't open their noise controls yet."
                font.pixelSize: Style.font.body
                font.bold: true
              }
              PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Bluetooth has to introduce itself as an Apple device. Add the line below to /etc/bluetooth/main.conf, restart bluetooth, and reconnect."
                font.pixelSize: Style.font.bodySmall
              }
              PlainLabel {
                width: parent.width
                text: "DeviceID = bluetooth:004C:0000:0000"
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }
            }
          }
        }

        // ====================================================================
        // TAB 2: EQUALIZER (Sound Presets + 5-Band Graphic EQ + Clear Bass)
        // ====================================================================
        Column {
          id: eqTabView
          visible: root.activeTab === "eq"
          width: parent.width
          spacing: Style.space(10)

          // ---- Unsupported or Disconnected Fallback Card
          Rectangle {
            visible: !root.st.connected || !root.eqState.available
            width: parent.width
            height: Style.space(96)
            color: "transparent"
            border.width: 1
            border.color: root.lineColor
            radius: Style.cornerRadius

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(6)

              PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰺢  Hardware DSP Equalizer"
                font.pixelSize: Style.font.body
                font.bold: true
              }
              PlainLabel {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.st.connected
                  ? "This headset model does not expose onboard DSP equalizer registers over Bluetooth. Use the Audio tab to switch codecs and latency."
                  : "Connect a supported Sony MDR headset to adjust its 5-band hardware equalizer, Clear Bass, and sound presets."
                font.pixelSize: Style.font.bodySmall
                color: root.dimColor
              }
            }
          }

          // ---- Sound Presets 3x3 Chip Grid
          Column {
            visible: root.st.connected && root.eqState.available
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Style.space(16)

              PlainLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SOUND PRESETS"
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }

              PlainLabel {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "[Reset Flat]"
                font.pixelSize: Style.font.caption
                color: root.eqState.preset !== "off" ? root.accentColor : root.dimColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (root.service) root.service.resetEq()
                  }
                }
              }
            }

            Grid {
              id: presetGrid
              width: parent.width
              columns: 3
              spacing: Style.space(6)

              Repeater {
                model: Model.EQ_PRESETS

                Rectangle {
                  required property var modelData
                  readonly property bool active: root.eqState.preset === modelData.key

                  width: Math.floor((presetGrid.width - presetGrid.spacing * 2) / 3)
                  height: Style.space(28)
                  radius: Style.cornerRadius
                  color: active ? root.selBgColor : (presetMouse.containsMouse ? root.trackBgColor : "transparent")
                  border.width: 1
                  border.color: active ? root.accentColor : root.lineColor

                  PlainLabel {
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: Style.font.bodySmall
                    font.bold: active
                    color: active ? root.fg : root.dimColor
                  }

                  MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      if (root.service) root.service.setEqPreset(modelData.key)
                    }
                  }
                }
              }
            }
          }

          // ---- 5-Band Vertical Graphic EQ (-10 to +10 dB)
          Column {
            visible: root.st.connected && root.eqState.available
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Style.space(16)

              PlainLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "5-BAND GRAPHIC EQ (-10 TO +10 dB)"
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }

              PlainLabel {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Click or drag bars"
                font.pixelSize: 10
                color: root.dimColor
              }
            }

            Rectangle {
              id: eqStage
              width: parent.width
              height: Style.space(138)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              radius: Style.cornerRadius

              // Center 0 dB reference line across the fader stage
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                y: Math.round(parent.height * 0.50)
                height: 1
                color: root.lineColor
              }

              Row {
                id: bandsRow
                anchors.fill: parent
                anchors.margins: Style.space(8)

                Repeater {
                  model: 5

                  Item {
                    required property int index
                    readonly property int bandVal: {
                      var b = root.eqState.bands || [0, 0, 0, 0, 0]
                      return Number(b[index] || 0)
                    }
                    readonly property string freqLabel: Model.EQ_BAND_LABELS[index] || ""

                    width: Math.floor(bandsRow.width / 5)
                    height: bandsRow.height

                    // Top dB readout (+4, 0, -2)
                    PlainLabel {
                      id: dbReadout
                      anchors.top: parent.top
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: (bandVal > 0 ? "+" : "") + String(bandVal)
                      font.pixelSize: Style.font.caption
                      font.bold: bandVal !== 0
                      color: bandVal > 0 ? root.accentColor : (bandVal < 0 ? root.fg : root.dimColor)
                    }

                    // Vertical Fader Track
                    Item {
                      id: vTrackWrap
                      anchors.top: dbReadout.bottom
                      anchors.bottom: freqText.top
                      anchors.topMargin: Style.space(4)
                      anchors.bottomMargin: Style.space(4)
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Style.space(32)

                      Rectangle {
                        id: vTrack
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(8)
                        height: parent.height
                        radius: 4
                        color: root.trackBgColor

                        // Bidirectional fill from center (0 dB)
                        Rectangle {
                          readonly property real midY: vTrack.height / 2.0
                          readonly property real normMag: Math.min(1.0, Math.abs(bandVal) / 10.0)
                          readonly property real barH: Math.max(2, Math.round(midY * normMag))

                          x: 0
                          width: parent.width
                          y: bandVal >= 0 ? Math.round(midY - barH) : Math.round(midY)
                          height: bandVal === 0 ? 2 : barH
                          radius: 3
                          color: bandVal > 0 ? root.accentColor : (bandVal < 0 ? root.fg : root.dimColor)
                        }

                        // Thumb knob
                        Rectangle {
                          readonly property real ratioFromTop: (10.0 - bandVal) / 20.0
                          anchors.horizontalCenter: parent.horizontalCenter
                          width: Style.space(16)
                          height: Style.space(6)
                          radius: 3
                          y: Math.max(0, Math.min(vTrack.height - height, Math.round(vTrack.height * ratioFromTop - height / 2)))
                          color: bandVal !== 0 ? root.accentColor : root.fg
                          border.width: 1
                          border.color: root.lineColor
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        function applyY(my) {
                          if (!root.service) return
                          var clampedY = Math.max(0, Math.min(height, my))
                          var rawVal = 10.0 - (clampedY / Math.max(1, height)) * 20.0
                          var target = Math.max(-10, Math.min(10, Math.round(rawVal)))
                          root.service.setEqBand(index, target)
                        }
                        onClicked: function(mouse) { applyY(mouse.y) }
                        onPositionChanged: function(mouse) {
                          if (pressed) applyY(mouse.y)
                        }
                        onWheel: function(wheel) {
                          var step = wheel.angleDelta.y > 0 ? 1 : -1
                          root.service.setEqBand(index, bandVal + step)
                        }
                      }
                    }

                    // Bottom Frequency Label (400, 1k, 2.5k, 6.3k, 16k)
                    PlainLabel {
                      id: freqText
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: freqLabel
                      font.pixelSize: Style.font.caption
                      color: root.dimColor
                    }
                  }
                }
              }
            }
          }

          // ---- Clear Bass Horizontal Slider (-10 to +10)
          Column {
            visible: root.st.connected && root.eqState.available
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Style.space(18)

              PlainLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEAR BASS"
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }

              PlainLabel {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (root.eqState.clearBass > 0 ? "+" : "") + String(root.eqState.clearBass)
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: root.eqState.clearBass > 0 ? root.accentColor : root.fg
              }
            }

            Item {
              id: cbTrackWrap
              width: parent.width
              height: Style.space(22)

              Rectangle {
                id: cbTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Style.space(6)
                radius: 3
                color: root.trackBgColor

                // Center 0 tick
                Rectangle {
                  x: Math.round(parent.width / 2)
                  y: -2
                  width: 1
                  height: parent.height + 4
                  color: root.dimColor
                }

                // Bidirectional fill from center
                Rectangle {
                  readonly property real midX: cbTrack.width / 2.0
                  readonly property int cbVal: root.eqState.clearBass
                  readonly property real spanW: Math.round(midX * (Math.min(10, Math.abs(cbVal)) / 10.0))

                  x: cbVal >= 0 ? Math.round(midX) : Math.round(midX - spanW)
                  width: Math.max(2, spanW)
                  height: parent.height
                  radius: 3
                  color: cbVal > 0 ? root.accentColor : root.fg
                }
              }

              MouseArea {
                anchors.fill: parent
                preventStealing: true
                function applyCbX(mx) {
                  if (!root.service) return
                  var ratio = Math.max(0, Math.min(1, mx / Math.max(1, width)))
                  var target = Math.max(-10, Math.min(10, Math.round(-10 + ratio * 20)))
                  root.service.setClearBass(target)
                }
                onClicked: function(mouse) { applyCbX(mouse.x) }
                onPositionChanged: function(mouse) {
                  if (pressed) applyCbX(mouse.x)
                }
                onWheel: function(wheel) {
                  var step = wheel.angleDelta.y > 0 ? 1 : -1
                  root.service.setClearBass(root.eqState.clearBass + step)
                }
              }
            }
          }
        }

        // ====================================================================
        // TAB 3: AUDIO (Codec Switcher + Latency / PipeWire Quantum)
        // ====================================================================
        Column {
          id: audioTabView
          visible: root.activeTab === "audio"
          width: parent.width
          spacing: Style.space(12)

          // ---- Disconnected Empty State
          Rectangle {
            visible: !root.st.connected
            width: parent.width
            height: Style.space(82)
            color: "transparent"
            border.width: 1
            border.color: root.lineColor
            radius: Style.cornerRadius

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)

              PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰓃  No Bluetooth Audio Card"
                font.pixelSize: Style.font.body
                font.bold: true
              }
              PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Connect headphones to switch A2DP codecs and PipeWire buffer quantum."
                font.pixelSize: Style.font.bodySmall
                color: root.dimColor
              }
            }
          }

          // ---- Audio Codec Segmented Row
          Column {
            visible: root.st.connected
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Style.space(16)

              PlainLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "BLUETOOTH AUDIO CODEC"
                font.pixelSize: Style.font.caption
                color: root.dimColor
              }

              PlainLabel {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Active: " + Model.cleanText(root.st.codec || "A2DP", 16)
                font.pixelSize: Style.font.caption
                font.bold: true
                color: root.accentColor
              }
            }

            Rectangle {
              id: codecBar
              visible: (root.st.codecs || []).length > 0
              width: parent.width
              height: Style.space(34)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              radius: Style.cornerRadius

              Row {
                anchors.fill: parent

                Repeater {
                  model: root.st.codecs || []

                  Item {
                    required property var modelData
                    required property int index
                    readonly property bool active: modelData.active === true
                    readonly property int count: (root.st.codecs || []).length

                    width: Math.floor(codecBar.width / Math.max(1, count))
                    height: codecBar.height

                    Rectangle {
                      anchors.fill: parent
                      color: active ? root.selBgColor : (codecMouse.containsMouse ? root.trackBgColor : "transparent")
                    }

                    Rectangle {
                      visible: active
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: 2
                      color: root.accentColor
                    }

                    Rectangle {
                      visible: index < count - 1
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: 1
                      color: root.lineColor
                    }

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(3)

                      PlainLabel {
                        text: modelData.label
                        font.pixelSize: Style.font.body
                        font.bold: active
                        color: active ? root.fg : root.dimColor
                      }

                      PlainLabel {
                        visible: !!modelData.hiRes
                        text: "◆"
                        font.pixelSize: 8
                        color: active ? root.accentColor : root.dimColor
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      id: codecMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: {
                        if (root.service) root.service.setCodec(modelData.profile)
                      }
                    }
                  }
                }
              }
            }

            PlainLabel {
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                var c = String(root.st.codec || "").toUpperCase()
                if (c === "LDAC") return "◆ Hi-Res Audio active (up to 990 kbps / 96 kHz). Switch to AAC or SBC-XQ if wireless interference occurs."
                if (c === "AAC" || c === "SBC-XQ") return "Balanced high-stability stereo A2DP profile with low packet drop."
                if (c === "MSBC" || c === "CVSD") return "Bidirectional hands-free headset profile (microphone enabled, mono/voice grade)."
                return "Select an A2DP sink profile above to switch codec on the fly."
              }
              font.pixelSize: Style.font.caption
              color: root.dimColor
            }
          }

          // ---- Latency & Buffer Segmented Row
          Column {
            visible: root.st.connected
            width: parent.width
            spacing: Style.space(6)

            PlainLabel {
              text: "LATENCY & PIPEWIRE BUFFER QUANTUM"
              font.pixelSize: Style.font.caption
              color: root.dimColor
            }

            Rectangle {
              id: latencyBar
              width: parent.width
              height: Style.space(34)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              radius: Style.cornerRadius

              Row {
                anchors.fill: parent

                Repeater {
                  model: Model.LATENCY_MODES

                  Item {
                    required property var modelData
                    required property int index
                    readonly property bool active: (root.st.latencyMode || "balanced") === modelData.key
                    readonly property int count: Model.LATENCY_MODES.length

                    width: Math.floor(latencyBar.width / Math.max(1, count))
                    height: latencyBar.height

                    Rectangle {
                      anchors.fill: parent
                      color: active ? root.selBgColor : (latencyMouse.containsMouse ? root.trackBgColor : "transparent")
                    }

                    Rectangle {
                      visible: active
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: 2
                      color: root.accentColor
                    }

                    Rectangle {
                      visible: index < count - 1
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: 1
                      color: root.lineColor
                    }

                    PlainLabel {
                      anchors.centerIn: parent
                      text: modelData.icon + "  " + modelData.label
                      font.pixelSize: Style.font.body
                      font.bold: active
                      color: active ? root.fg : root.dimColor
                    }

                    MouseArea {
                      id: latencyMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: {
                        if (root.service) root.service.setLatencyMode(modelData.key)
                      }
                    }
                  }
                }
              }
            }

            PlainLabel {
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                var lm = root.st.latencyMode || "balanced"
                if (lm === "low") return "Quantum 256 (~5 ms) — Tight lip-sync and gaming response."
                if (lm === "hifi") return "Quantum 2048 (~42 ms) — Deep buffer for glitch-free 990 kbps LDAC playback."
                return "Dynamic Quantum (0) — PipeWire automatically scales buffer size per application."
              }
              font.pixelSize: Style.font.caption
              color: root.dimColor
            }
          }
        }

        // ====================================================================
        // TAB 4: SETTINGS (Bar, Alerts, Ear Detection)
        // ====================================================================
        Column {
          id: settingsTabView
          visible: root.activeTab === "settings"
          width: parent.width
          spacing: Style.space(8)

          PlainLabel {
            text: "BAR WIDGET"
            font.pixelSize: Style.font.caption
            color: root.dimColor
          }

          // Show battery percent
          Item {
            width: parent.width
            height: Style.space(26)
            PlainLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Show battery percent"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: Style.space(14)
              color: "transparent"
              border.width: 1
              border.color: (root.service && root.service.showBattery) ? root.fg : root.dimColor
              Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                x: (root.service && root.service.showBattery) ? parent.width - width - 3 : 3
                color: (root.service && root.service.showBattery) ? root.fg : root.dimColor
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.persistSettings({ showBattery: !(root.service && root.service.showBattery) })
            }
          }

          // Hide when nothing is connected
          Item {
            width: parent.width
            height: Style.space(26)
            PlainLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Hide when nothing is connected"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: Style.space(14)
              color: "transparent"
              border.width: 1
              border.color: (root.service && root.service.hideWhenDisconnected) ? root.fg : root.dimColor
              Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                x: (root.service && root.service.hideWhenDisconnected) ? parent.width - width - 3 : 3
                color: (root.service && root.service.hideWhenDisconnected) ? root.fg : root.dimColor
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.persistSettings({ hideWhenDisconnected: !(root.service && root.service.hideWhenDisconnected) })
            }
          }

          PlainLabel {
            text: "BATTERY ALERTS"
            font.pixelSize: Style.font.caption
            color: root.dimColor
          }

          // Warn threshold
          Item {
            width: parent.width
            height: Style.space(26)
            PlainLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Warn when a battery drops below"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(64)
              height: Style.space(22)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              PlainLabel {
                anchors.centerIn: parent
                text: (root.service ? root.service.lowThreshold : 15) + "% ▾"
                font.pixelSize: Style.font.bodySmall
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.cycleThreshold()
            }
          }

          // Notify on low battery
          Item {
            width: parent.width
            height: Style.space(26)
            PlainLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Notify on low battery"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: Style.space(14)
              color: "transparent"
              border.width: 1
              border.color: (root.service && root.service.notifyLow) ? root.fg : root.dimColor
              Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                x: (root.service && root.service.notifyLow) ? parent.width - width - 3 : 3
                color: (root.service && root.service.notifyLow) ? root.fg : root.dimColor
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.persistSettings({ notifyLow: !(root.service && root.service.notifyLow) })
            }
          }

          PlainLabel {
            text: "PLAYBACK"
            font.pixelSize: Style.font.caption
            color: root.dimColor
          }

          // Pause when taken off
          Item {
            width: parent.width
            height: Style.space(26)
            PlainLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Pause when taken off"
              font.pixelSize: Style.font.body
            }
            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(84)
              height: Style.space(22)
              color: "transparent"
              border.width: 1
              border.color: root.lineColor
              PlainLabel {
                anchors.centerIn: parent
                text: (root.service ? root.service.earBehavior : "One out") + " ▾"
                font.pixelSize: Style.font.bodySmall
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.cycleEarBehavior()
            }
          }

          PlainLabel {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Saved to this widget's entry in shell.json. Nothing else is written."
            font.pixelSize: Style.font.caption
            color: root.dimColor
          }
        }

        // ====================================================================
        // QUICK MIC MUTE & VOLUME STRIP (Docked at bottom, PipeWire sync)
        // ====================================================================
        Rectangle {
          id: quickVolumeStrip
          visible: root.st.connected
          width: parent.width
          height: Style.space(34)
          color: "transparent"
          border.width: 1
          border.color: root.lineColor
          radius: Style.cornerRadius

          readonly property real vol: root.service ? root.service.outputVolume : 0.75
          readonly property bool outMuted: root.service ? root.service.outputMuted : false
          readonly property bool micMuted: root.service ? root.service.micMuted : false

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            // Left: Output Mute / Volume icon button
            Rectangle {
              id: outMuteBtn
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: outMuteMouse.containsMouse ? root.trackBgColor : "transparent"

              PlainLabel {
                anchors.centerIn: parent
                text: quickVolumeStrip.outMuted ? "󰝟" : (quickVolumeStrip.vol > 0.5 ? "󰕾" : "󰖀")
                font.pixelSize: Style.font.body
                color: quickVolumeStrip.outMuted ? root.urgentColor : root.fg
              }

              MouseArea {
                id: outMuteMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.service) root.service.toggleOutputMute()
                }
              }
            }

            // Center: Interactive Volume Slider
            Item {
              id: volSliderWrap
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - outMuteBtn.width - micMuteBtn.width - volText.implicitWidth - Style.space(34)
              height: parent.height

              Rectangle {
                id: volTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Style.space(6)
                radius: 3
                color: root.trackBgColor

                Rectangle {
                  width: Math.max(0, Math.min(parent.width, Math.round(parent.width * (quickVolumeStrip.outMuted ? 0 : quickVolumeStrip.vol))))
                  height: parent.height
                  radius: 3
                  color: quickVolumeStrip.outMuted ? root.dimColor : root.accentColor
                }

                Rectangle {
                  visible: !quickVolumeStrip.outMuted
                  width: Style.space(12)
                  height: Style.space(12)
                  radius: 6
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.max(0, Math.min(parent.width - width, Math.round(parent.width * quickVolumeStrip.vol - width / 2)))
                  color: root.accentColor
                  border.width: 1
                  border.color: root.lineColor
                }
              }

              MouseArea {
                anchors.fill: parent
                function applyVol(mx) {
                  if (!root.service) return
                  var ratio = Math.max(0, Math.min(1.0, mx / Math.max(1, width)))
                  root.service.setOutputVolume(ratio)
                }
                onClicked: function(mouse) { applyVol(mouse.x) }
                onPositionChanged: function(mouse) {
                  if (pressed) applyVol(mouse.x)
                }
                onWheel: function(wheel) {
                  if (root.service) root.service.adjustOutputVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                }
              }
            }

            // Volume readout text (e.g. 75% or Muted)
            PlainLabel {
              id: volText
              anchors.verticalCenter: parent.verticalCenter
              text: quickVolumeStrip.outMuted ? "Muted" : (Math.round(quickVolumeStrip.vol * 100) + "%")
              font.pixelSize: Style.font.caption
              font.bold: true
              color: quickVolumeStrip.outMuted ? root.urgentColor : root.fg
            }

            // Subtle vertical separator
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Style.space(18)
              color: root.lineColor
            }

            // Right: Quick Mic Mute Toggle Button
            Rectangle {
              id: micMuteBtn
              anchors.verticalCenter: parent.verticalCenter
              width: micRow.implicitWidth + Style.space(14)
              height: Style.space(24)
              radius: Style.cornerRadius
              color: quickVolumeStrip.micMuted
                ? Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.16)
                : (micMouse.containsMouse ? root.trackBgColor : "transparent")
              border.width: 1
              border.color: quickVolumeStrip.micMuted ? root.urgentColor : root.lineColor

              Row {
                id: micRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                PlainLabel {
                  anchors.verticalCenter: parent.verticalCenter
                  text: quickVolumeStrip.micMuted ? "󰍭" : "󰍬"
                  font.pixelSize: Style.font.bodySmall
                  color: quickVolumeStrip.micMuted ? root.urgentColor : root.fg
                }

                PlainLabel {
                  anchors.verticalCenter: parent.verticalCenter
                  text: quickVolumeStrip.micMuted ? "Muted" : "Mic Live"
                  font.pixelSize: Style.font.caption
                  font.bold: quickVolumeStrip.micMuted
                  color: quickVolumeStrip.micMuted ? root.urgentColor : root.dimColor
                }
              }

              MouseArea {
                id: micMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.service) root.service.toggleMic()
                }
              }
            }
          }
        }

        // ====================================================================
        // PERSISTENT FOOTER HINT
        // ====================================================================
        Item {
          width: parent.width
          height: Style.space(16)

          PlainLabel {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "1-4 tabs · m mic · v mute · +/- vol · esc close"
            font.pixelSize: 10
            color: root.dimColor
          }

          PlainLabel {
            visible: root.st.busy === true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "[Try again]"
            font.pixelSize: Style.font.caption
            color: root.fg

            MouseArea {
              anchors.fill: parent
              onClicked: {
                if (root.service) root.service.retryConnection()
              }
            }
          }
        }
      }
    }
  }
}
