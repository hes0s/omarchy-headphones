# Headphones Companion (`eh0.headphones`)

[![CI](https://github.com/hes0s/omarchy-headphones/actions/workflows/ci.yml/badge.svg)](https://github.com/hes0s/omarchy-headphones/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A unified native headphone companion bar widget and control panel for **Omarchy** and **Quickshell**.

Supports Sony WH/WF series (via MDR protocol), Apple AirPods (via BLE telemetry), and standard Bluetooth audio devices (via BlueZ and PipeWire), complete with Google Fast Pair advertisement, hardware EQ presets, codec/latency switching, and quick volume/mic controls.

![Headphones Companion Preview](preview.png)

---

## Features

- **Segmented Noise Control**: Instantly switch between **Off**, **Active Noise Cancellation (ANC)**, and **Ambient Sound** for supported headsets (Sony MDR, AirPods).
- **Comprehensive Battery Telemetry**:
  - Live battery percentage on the bar widget.
  - Per-earbud (Left, Right) and charging case percentages for true wireless earbuds.
  - Configurable low-battery visual warning and desktop notifications.
- **Hardware Equalizer & Sound Presets**:
  - 5-band hardware EQ (-10 dB to +10 dB) plus ClearBass for Sony headphones.
  - Built-in sound presets: *Off*, *Bass Boost*, *Vocal*, *Treble Boost*, and *Custom*.
  - Live persistent state synced directly to headphone hardware.
- **Quick Bluetooth Codec & Latency Switcher**:
  - Seamlessly switch between LDAC, AAC, aptX, aptX HD, SBC-XQ, and standard SBC through PipeWire.
  - One-click latency profiles: *Balanced / Standard*, *Pro Audio / Ultra Low Latency* (64–128 samples), and *Hi-Res Audio*.
- **Quick Mic Mute & Volume Strip**:
  - Docked at the bottom of the panel across all tabs for fast, frictionless audio control.
  - Interactive volume slider with smooth dragging and scroll-wheel adjustment (`±5%`).
  - Single-click microphone mute toggle with live reactive state (`Mic Live` / `Mic Muted`).
- **Google Fast Pair (GFPS)**:
  - Broadcasts Fast Pair BLE advertisements to simplify pairing with nearby devices.
- **Smart Features**:
  - Automatic pause playback when removing headphones (wear detection).
  - Quick focus-on-voice toggle for ambient awareness.
- **Full Keyboard Navigation**:
  - `1` - `4`: Switch between tabs (*Control*, *Equalizer*, *Audio*, *Settings*)
  - `m`: Quick toggle microphone mute
  - `v`: Quick toggle output audio mute
  - `+` / `-`: Increase / decrease output volume
  - `Esc`: Close panel

---

## Requirements

The companion plugin relies on standard Linux audio and Bluetooth stacks:
- **Omarchy Shell** / **Quickshell**
- **PipeWire** & `wireplumber` (for audio routing and Bluetooth codec negotiation)
- **BlueZ** (for Bluetooth device discovery and battery reporting)
- **Python 3** (included on Omarchy / Arch Linux)
- `python3-dbus` (standard package for D-Bus integration)

---

## Installation

### Direct via Git (Current)
Install directly into Omarchy using the `omarchy` CLI:
```bash
omarchy plugin add https://github.com/hes0s/omarchy-headphones.git --enable
```

### Marketplace
```bash
omarchy plugin add eh0.headphones --enable
```

---

## Configuration

Settings can be customized in the Omarchy Bar Settings UI or via `manifest.json` schema:

| Setting Key | Type | Default | Description |
|---|---|---|---|
| `showBattery` | enum (`true`/`false`) | `true` | Display battery percentage directly on the status bar |
| `hideWhenDisconnected` | enum (`true`/`false`) | `true` | Hide the bar widget when no headphones are connected |
| `lowThreshold` | integer (5–40) | `15` | Battery level threshold for warning highlight |
| `notifyLow` | enum (`true`/`false`) | `true` | Send system notification when battery drops below threshold |
| `earBehavior` | enum | `One out` | Behavior when removing an earbud (`One out`, `Both out`, `Never`) |

---

## Testing & Validation

The codebase includes an automated test suite verifying state parsing, EQ normalization, battery calculations, and bridge IPC:

```bash
# Run unit tests
node tests/model.test.js

# Test Python bridge
./bin/headphone-bridge selftest

# Validate plugin manifest with Omarchy CLI
omarchy plugin validate .
```

---

## Removal

To disable and remove the plugin:
```bash
omarchy plugin remove eh0.headphones
```

---

## License

This project is licensed under the [MIT License](LICENSE).
