bluez_monitor.enabled = true

bluez_monitor.properties["with-logind"] = false
bluez_monitor.properties["bluez5.roles"] = "[ a2dp_sink a2dp_source ]"
bluez_monitor.properties["bluez5.default.rate"] = 48000
bluez_monitor.properties["bluez5.default.channels"] = 2
bluez_monitor.properties["bluez5.dummy-avrcp-player"] = true
bluez_monitor.properties["bluez5.enable-sbc-xq"] = true
bluez_monitor.properties["bluez5.enable-hw-volume"] = false

table.insert(bluez_monitor.rules, {
  matches = {
    {
      { "device.name", "matches", "bluez_card.*" },
    },
  },
  apply_properties = {
    ["bluez5.auto-connect"] = "[ a2dp_sink a2dp_source ]",
    ["bluez5.hw-volume"] = "[]",
  },
})

table.insert(bluez_monitor.rules, {
  matches = {
    {
      { "node.name", "matches", "bluez_input.*" },
    },
  },
  apply_properties = {
    ["bluez5.media-source-role"] = "playback",
  },
})
