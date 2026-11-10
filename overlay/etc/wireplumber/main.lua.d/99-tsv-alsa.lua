alsa_monitor.rules = alsa_monitor.rules or {}

-- Prefer ACP/UCM routing on the Qualcomm QDSP6 card.
-- api.alsa.disable-mmap is a PCM-node property, not a card property: setting
-- it here has no effect (see the node rules below).
table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "device.name", "equals", "alsa_card.platform-c051000.sound-card" },
    },
  },
  apply_properties = {
    ["api.alsa.use-acp"] = true,
    ["api.alsa.use-ucm"] = true,
    ["api.acp.auto-profile"] = true,
    ["api.acp.auto-port"] = true,
  },
})

-- Speaker (MultiMedia1 -> QUAT_MI2S_RX -> TAS5782M): fixed S16LE 48kHz stereo.
--
-- Q6ASM reports the hardware position in whole periods only. Keep the
-- PipeWire quantum equal to one ALSA period, reserve explicit pointer-jitter
-- headroom, and disable batching so stream joins/leaves do not change the
-- graph quantum. Playback and capture share the same ADSP clock: give them
-- the same clock.name so PipeWire does not rate-match one against the other.
table.insert(alsa_monitor.rules, {
  matches = {
    { { "node.name", "matches", "alsa_output.platform-c051000.sound-card.*" } },
  },
  apply_properties = {
    ["node.pause-on-idle"] = false,
    ["session.suspend-timeout-seconds"] = 0,
    ["audio.format"] = "S16LE",
    ["audio.rate"] = 48000,
    ["audio.channels"] = 2,
    ["api.alsa.disable-mmap"] = true,
    ["api.alsa.disable-batch"] = true,
    ["api.alsa.period-size"] = 960,
    ["api.alsa.headroom"] = 4096,
    ["node.force-quantum"] = 960,
    ["clock.name"] = "api.alsa.cd18781y",
    ["priority.driver"] = 2000,
  },
})

-- Dual DMIC Array (MultiMedia2 <- TERT_MI2S_TX <- DMIC1+DMIC2 @ 2.4MHz):
-- Native PipeWire capture enabled directly on Kernel 7.3.0-tsv (Patches 0502 & 0903).
table.insert(alsa_monitor.rules, {
  matches = {
    { { "node.name", "matches", "alsa_input.platform-c051000.sound-card.*" } },
  },
  apply_properties = {
    ["node.pause-on-idle"] = false,
    ["session.suspend-timeout-seconds"] = 0,
    ["audio.format"] = "S16LE",
    ["audio.rate"] = 48000,
    ["audio.channels"] = 2,
    ["api.alsa.disable-mmap"] = true,
    ["api.alsa.period-size"] = 960,
    ["api.alsa.headroom"] = 768,
    ["clock.name"] = "api.alsa.cd18781y",
  },
})

-- Hide the extra PCM devices the QDSP6 card exposes (there is no headset
-- jack on this device); they would otherwise appear as selectable nodes.
table.insert(alsa_monitor.rules, {
  matches = {
    { { "node.name", "equals", "alsa_output.platform-c051000.sound-card.playback.2.0" } },
    { { "node.name", "equals", "alsa_output.platform-c051000.sound-card.playback.4.0" } },
    { { "node.name", "equals", "alsa_input.platform-c051000.sound-card.capture.4.0" } },
  },
  apply_properties = {
    ["node.disabled"] = true,
  },
})