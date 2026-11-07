alsa_monitor.rules = alsa_monitor.rules or {}

-- Prefer ACP/UCM routing and disable mmap probes on Qualcomm QDSP6 card.
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
    ["api.alsa.disable-mmap"] = true,
  },
})

-- Speaker (MultiMedia1 -> QUAT_MI2S_RX -> TAS5782M): fixed S16LE 48kHz stereo.
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
    ["api.alsa.period-size"] = 960,
    ["api.alsa.headroom"] = 1024,
  },
})
