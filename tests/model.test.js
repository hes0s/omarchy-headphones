const assert = require("assert")
const Model = require("../Model.js")

// 1. cleanText strips <, >, & and control characters and caps length
assert.strictEqual(Model.cleanText("<b>WH-1000XM4 & AirPods</b>\n\x00"), "bWH-1000XM4  AirPods/b".replace("  ", " "))
assert.strictEqual(Model.cleanText("a".repeat(200), 20).length, 20)

// 2. MAC validation
assert.strictEqual(Model.isValidMac("80:99:E7:C5:44:06"), true)
assert.strictEqual(Model.isValidMac("80:99:E7:C5:44"), false)
assert.strictEqual(Model.isValidMac("--help"), false)

// 3. Settings normalization (string coercion + integer clamping)
const s = Model.normalizeSettings({
  showBattery: "false",
  hideWhenDisconnected: "true",
  lowThreshold: "99",
  notifyLow: "0",
  earBehavior: "Both out"
})
assert.strictEqual(s.showBattery, false)
assert.strictEqual(s.hideWhenDisconnected, true)
assert.strictEqual(s.lowThreshold, 40)
assert.strictEqual(s.notifyLow, false)
assert.strictEqual(s.earBehavior, "Both out")

// 4. Parse bluetoothctl info for WH-1000XM4
const xm4InfoText = `
Device 80:99:E7:C5:44:06 (public)
\tName: WH-1000XM4
\tIcon: audio-headset
\tUUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)
\tUUID: Vendor specific           (96cc203e-5068-46ad-b32d-e316f5e069ba)
\tModalias: usb:v054Cp0D58d0301
`
const parsedXm4 = Model.parseBluetoothctlInfo(xm4InfoText)
assert.strictEqual(parsedXm4.name, "WH-1000XM4")
assert.ok(parsedXm4.uuids.includes(Model.SONY_UUID_V1))
const drvXm4 = Model.detectDriver(parsedXm4, "WH-1000XM4")
assert.strictEqual(drvXm4.driver, "sony")
assert.strictEqual(drvXm4.driverLabel, "SONY MDR V1")
assert.strictEqual(drvXm4.form, "overear")

// 5. Detect Apple AirPods by modalias or name
const drvPods = Model.detectDriver({ uuids: [], modalias: "bluetooth:v004Cp2014d0000", name: "AirPods Pro" })
assert.strictEqual(drvPods.driver, "airpods")
assert.strictEqual(drvPods.form, "earbuds")

// 6. Build cells for over-ear vs AirPods vs one-pod-in-case
const sonyCells = Model.buildCells(Model.debugFixture("sony-anc"))
assert.strictEqual(sonyCells.length, 1)
assert.strictEqual(sonyCells[0].value, 80)

const onePodCells = Model.buildCells(Model.debugFixture("one-pod"))
assert.strictEqual(onePodCells.length, 3)
assert.strictEqual(onePodCells[0].value, 64)
assert.strictEqual(onePodCells[1].value, null)
assert.strictEqual(onePodCells[1].placeholder, "In case")

// 7. Ear detection auto-pause state machine
assert.deepStrictEqual(
  Model.shouldPauseOnEar("One out", null, null, ["in_ear", "in_ear"], ["out_of_ear", "in_ear"]),
  { pause: true, resume: false }
)
assert.deepStrictEqual(
  Model.shouldPauseOnEar("One out", null, null, ["out_of_ear", "in_ear"], ["in_ear", "in_ear"]),
  { pause: false, resume: true }
)

// 8. Low battery deduplication
const lowState = Model.debugFixture("low")
const check1 = Model.lowBatteryComponents(lowState, 15, {})
assert.strictEqual(check1.alerts.length, 2)
const check2 = Model.lowBatteryComponents(lowState, 15, check1.warned)
assert.strictEqual(check2.alerts.length, 0)

// 9. Detect Google Fast Pair (GFPS) via UUID or name
const drvGfpsUuid = Model.detectDriver({ uuids: [Model.GFPS_UUID], name: "Nothing Ear (2)" })
assert.strictEqual(drvGfpsUuid.driver, "gfps")
assert.strictEqual(drvGfpsUuid.driverLabel, "FAST PAIR")
assert.strictEqual(drvGfpsUuid.uuid, Model.GFPS_UUID)

const drvPixel = Model.detectDriver({ uuids: [], name: "Pixel Buds Pro" })
assert.strictEqual(drvPixel.driver, "gfps")
assert.strictEqual(drvPixel.brand, "Google")
assert.strictEqual(drvPixel.form, "earbuds")

// 10. GFPS 3-cell battery layout & charging indicators
const gfpsState = Model.debugFixture("pixel-buds")
const gfpsCells = Model.buildCells(gfpsState)
assert.strictEqual(gfpsCells.length, 3)
assert.strictEqual(gfpsCells[0].label, "LEFT")
assert.strictEqual(gfpsCells[0].value, 95)
assert.strictEqual(gfpsCells[0].charging, false)
assert.strictEqual(gfpsCells[1].label, "RIGHT")
assert.strictEqual(gfpsCells[1].value, 90)
assert.strictEqual(gfpsCells[2].label, "CASE")
assert.strictEqual(gfpsCells[2].value, 80)
assert.strictEqual(gfpsCells[2].charging, true)

// 11. mergeBridgeLine with GFPS payload
const mergedGfps = Model.mergeBridgeLine({}, JSON.stringify({
  connected: true,
  address: "24:28:FD:88:99:AA",
  name: "Pixel Buds Pro 2",
  driver: "gfps",
  driverLabel: "FAST PAIR",
  battery: { single: null, left: 100, right: 90, case: 50, perBud: true, hasCase: true },
  charging: { single: false, left: true, right: false, case: false }
}))
assert.strictEqual(mergedGfps.driver, "gfps")
assert.strictEqual(mergedGfps.battery.left, 100)
assert.strictEqual(mergedGfps.charging.left, true)
assert.strictEqual(mergedGfps.battery.case, 50)

// 12. Parse pactl card JSON for Bluetooth codecs
const pactlSample = [
  {
    name: "alsa_card.pci-0000_63_00.1",
    active_profile: "off",
    profiles: { "off": { description: "Off", available: true } }
  },
  {
    name: "bluez_card.80_99_E7_C5_44_06",
    active_profile: "a2dp-sink",
    profiles: {
      "off": { description: "Off", sinks: 0, available: true },
      "a2dp-sink-sbc": { description: "High Fidelity Playback (A2DP Sink, codec SBC)", sinks: 1, available: true },
      "a2dp-sink-sbc_xq": { description: "High Fidelity Playback (A2DP Sink, codec SBC-XQ)", sinks: 1, available: true },
      "a2dp-sink-aac": { description: "High Fidelity Playback (A2DP Sink, codec AAC)", sinks: 1, available: true },
      "a2dp-sink": { description: "High Fidelity Playback (A2DP Sink, codec LDAC)", sinks: 1, available: true },
      "headset-head-unit": { description: "Headset Head Unit (HSP/HFP, codec MSBC)", sinks: 1, available: true }
    },
    properties: {
      "api.bluez5.address": "80:99:E7:C5:44:06"
    }
  }
]

const audioCard = Model.parseAudioCards(pactlSample, "80:99:E7:C5:44:06")
assert.ok(audioCard !== null)
assert.strictEqual(audioCard.cardName, "bluez_card.80_99_E7_C5_44_06")
assert.strictEqual(audioCard.activeProfile, "a2dp-sink")
assert.strictEqual(audioCard.activeCodec, "LDAC")
assert.strictEqual(audioCard.codecs.length, 5)
// Sorted by priority: LDAC (10) -> AAC (6) -> SBC-XQ (5) -> SBC (4) -> mSBC (2)
assert.strictEqual(audioCard.codecs[0].label, "LDAC")
assert.strictEqual(audioCard.codecs[0].hiRes, true)
assert.strictEqual(audioCard.codecs[0].active, true)
assert.strictEqual(audioCard.codecs[1].label, "AAC")
assert.strictEqual(audioCard.codecs[1].active, false)
assert.strictEqual(audioCard.codecs[2].label, "SBC-XQ")
assert.strictEqual(audioCard.codecs[3].label, "SBC")
assert.strictEqual(audioCard.codecs[4].label, "mSBC")
assert.strictEqual(audioCard.codecs[4].isMic, true)

// 13. Latency modes structure
assert.strictEqual(Model.LATENCY_MODES.length, 3)
assert.strictEqual(Model.LATENCY_MODES[0].key, "low")
assert.strictEqual(Model.LATENCY_MODES[0].quantum, 256)
assert.strictEqual(Model.LATENCY_MODES[1].key, "balanced")
assert.strictEqual(Model.LATENCY_MODES[1].quantum, 0)
assert.strictEqual(Model.LATENCY_MODES[2].key, "hifi")
assert.strictEqual(Model.LATENCY_MODES[2].quantum, 2048)

// 14. Hardware EQ normalization & mergeBridgeLine
const eqDefaultSony = Model.normalizeEq(null, "sony")
assert.strictEqual(eqDefaultSony.available, true)
assert.strictEqual(eqDefaultSony.preset, "off")
assert.deepStrictEqual(eqDefaultSony.bands, [0, 0, 0, 0, 0])

const eqClamped = Model.normalizeEq({ available: true, preset: "custom1", clearBass: 15, bands: [-20, 4, 1, 0, 99] }, "sony")
assert.strictEqual(eqClamped.preset, "manual")
assert.strictEqual(eqClamped.clearBass, 10)
assert.deepStrictEqual(eqClamped.bands, [-10, 4, 1, 0, 10])

const mergedSonyEq = Model.mergeBridgeLine({}, JSON.stringify({
  connected: true,
  driver: "sony",
  eq: { available: true, preset: "bass", clearBass: 7, bands: [4, 1, 0, 0, 0] }
}))
assert.strictEqual(mergedSonyEq.eq.available, true)
assert.strictEqual(mergedSonyEq.eq.preset, "bass")
assert.strictEqual(mergedSonyEq.eq.clearBass, 7)
assert.deepStrictEqual(mergedSonyEq.eq.bands, [4, 1, 0, 0, 0])

// 15. Volume & Mic Mute normalization
const mergedAudioState = Model.mergeBridgeLine({}, JSON.stringify({
  connected: true,
  outputVolume: 0.65,
  outputMuted: true,
  micMuted: false
}))
assert.strictEqual(mergedAudioState.outputVolume, 0.65)
assert.strictEqual(mergedAudioState.outputMuted, true)
assert.strictEqual(mergedAudioState.micMuted, false)

// 16. Ingress line bounds & sanitization
const oversizedPayload = JSON.stringify({ connected: true, name: "A".repeat(500), error: "B".repeat(500) })
const safeMerge = Model.mergeBridgeLine({}, oversizedPayload)
assert.strictEqual(safeMerge.connected, true)
assert.ok(safeMerge.name.length <= 128)
assert.ok(safeMerge.error.length <= 256)

// Invalid truncated JSON falls back gracefully without throwing
const truncated = oversizedPayload.slice(0, 50)
const fallback = Model.mergeBridgeLine({ connected: true }, truncated)
assert.strictEqual(fallback.connected, true)

console.log("All Model.js unit tests passed!")
