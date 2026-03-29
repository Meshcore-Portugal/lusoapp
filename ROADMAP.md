# MCAPPPT — MeshCore Companion App Portugal

## Roadmap

### Phase 1 — Foundation (Current: v0.1.x)

**Goal:** Working serial & BLE connection with basic messaging.

- [x] Project scaffolding (Flutter, Riverpod, GoRouter)
- [x] MeshCore Companion Protocol implementation
  - [x] KISS framing encoder/decoder
  - [x] Companion frame encoder (App → Radio)
  - [x] Companion frame decoder (Radio → App)
  - [x] Full command/response type definitions
- [x] Transport layer
  - [x] Abstract `RadioTransport` interface
  - [x] BLE transport (Nordic UART service)
  - [x] Serial/USB OTG transport
  - [x] Device scanning and discovery
- [x] Core UI screens
  - [x] Device connection screen (BLE + Serial scan)
  - [x] Channel chat (send/receive channel messages)
  - [x] Private chat (1:1 encrypted messaging)
  - [x] Radio configuration (LoRa params, TX power, presets)
  - [x] Contacts list (grouped by type)
  - [x] Settings screen (identity, connection management)
- [x] State management (Riverpod providers)
- [x] Portuguese (Portugal) UI language
- [x] Unit tests for protocol encoder/decoder
- [ ] Integration tests for transport layer mocks

---

### Phase 2 — Persistence & Reliability (v0.2.x)

**Goal:** Message history, offline support, robust reconnection.

- [ ] Local database (Isar)
  - [ ] Message history persistence
  - [ ] Contact cache (survive app restarts)
  - [ ] Channel list persistence
- [ ] Auto-reconnect logic
  - [ ] BLE reconnect on disconnect
  - [ ] Serial reconnect on USB re-plug
- [ ] Message delivery tracking
  - [ ] Pending/sent/confirmed/failed states
  - [ ] Retry on failure with exponential backoff
- [ ] Background message sync (`SYNC_NEXT` loop)
- [ ] Notification support (local notifications for new messages)
- [ ] Connection quality indicator (RSSI, SNR from `RxMeta`)
- [ ] Export/import contacts

---

### Phase 3 — Advanced Features (v0.3.x)

**Goal:** Full companion app parity with richer UX.

- [ ] Map view
  - [ ] Display contacts with GPS coordinates
  - [ ] Self-location via phone GPS
  - [ ] Path visualization between nodes
- [ ] Telemetry dashboard
  - [ ] Battery history chart
  - [ ] Sensor data (CayenneLPP decode)
  - [ ] Network statistics (RX/TX/Error counters)
- [ ] Path tracing
  - [ ] Visual hop-by-hop route display
  - [ ] Latency estimation
- [ ] Room server support
  - [ ] Browse/join MeshCore rooms
  - [ ] Room message list
- [ ] Multi-radio support
  - [ ] Connect to multiple radios simultaneously
  - [ ] Radio selector in UI

---

### Phase 4 — Community & Polish (v0.4.x)

**Goal:** Community features, localization, and release readiness.

- [ ] Full i18n framework
  - [ ] Portuguese (Portugal) — primary
  - [ ] English — secondary
  - [ ] Spanish — community contribution
- [ ] QR code sharing
  - [ ] Share own contact via QR
  - [ ] Scan to add contact
- [ ] Theme customization
  - [ ] Light/dark mode toggle
  - [ ] Custom accent colors
- [ ] Accessibility
  - [ ] Screen reader support
  - [ ] High contrast mode
  - [ ] Adjustable font sizes
- [ ] App icon and splash screen (Portuguese community branding)
- [ ] Google Play Store release
- [ ] F-Droid release
- [ ] iOS TestFlight release

---

### Phase 5 — Advanced Networking (v0.5.x)

**Goal:** Mesh network intelligence and advanced radio features.

- [ ] Mesh topology viewer
  - [ ] Visual network graph
  - [ ] Node discovery timeline
- [ ] Repeater management
  - [ ] View repeater status
  - [ ] Configure repeater settings (if admin)
- [ ] Channel management
  - [ ] Create/edit channels on radio
  - [ ] Channel encryption settings
- [ ] Firmware update over BLE/Serial
  - [ ] OTA firmware upload
  - [ ] Version check and notification
- [ ] Power management profiles
  - [ ] Low-power mode scheduling
  - [ ] TX power by time-of-day
- [ ] Data export
  - [ ] CSV export of contacts and messages
  - [ ] KML export for map data
  - [ ] Protocol log export for debugging

---

### Phase 6 — Integration & Ecosystem (v1.0.x)

**Goal:** Production-ready release with ecosystem integration.

- [ ] MeshFlare integration
  - [ ] Bridge to MQTT cluster
  - [ ] IRC federation gateway
- [ ] Meshtastic interop
  - [ ] Receive Meshtastic packets via MeshCore bridge
  - [ ] Cross-protocol contact resolution
- [ ] Webhook/automation support
  - [ ] Incoming message webhooks
  - [ ] IFTTT/Home Assistant integration
- [ ] Widget support
  - [ ] Android home screen widget (last messages, battery)
  - [ ] iOS widget
- [ ] Desktop support
  - [ ] Windows (serial + BLE)
  - [ ] Linux (serial + BLE)
  - [ ] macOS (BLE)
- [ ] Plugin architecture
  - [ ] Community-developed plugins
  - [ ] Sensor visualization plugins

---

## Technical Architecture

```
┌─────────────────────────────────────────────────┐
│                   Flutter App                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  UI/UX   │  │ Providers│  │  Local DB     │  │
│  │ (Screens)│◄─┤(Riverpod)│◄─┤  (Isar)       │  │
│  └──────────┘  └────┬─────┘  └───────────────┘  │
│                     │                             │
│              ┌──────┴──────┐                      │
│              │RadioService │                      │
│              │(Coordinator)│                      │
│              └──────┬──────┘                      │
│                     │                             │
│           ┌─────────┴─────────┐                   │
│           │  Protocol Layer   │                   │
│           │ ┌───────┐ ┌─────┐ │                   │
│           │ │Encoder│ │Decod│ │                   │
│           │ └───────┘ └─────┘ │                   │
│           └─────────┬─────────┘                   │
│                     │                             │
│           ┌─────────┴─────────┐                   │
│           │  Transport Layer  │                   │
│           │ ┌─────┐ ┌──────┐ │                   │
│           │ │ BLE │ │Serial│ │                   │
│           │ └─────┘ └──────┘ │                   │
│           └───────────────────┘                   │
└─────────────────────────────────────────────────┘
                     │
                     ▼
            ┌────────────────┐
            │ MeshCore Radio │
            │  (ESP32/nRF52) │
            └────────────────┘
```

## EU868 Regulatory Notes

The app defaults to EU868 LoRa parameters compliant with Portuguese/EU regulations:
- **Frequency:** 869.4–869.65 MHz (SRD Band)
- **Duty Cycle:** 10% max (Short Range Devices)
- **TX Power:** 14 dBm ERP max (25 mW)
- **Bandwidth:** 62.5–125 kHz typical for LoRa

Users are responsible for ensuring their radio configuration complies with ANACOM (Autoridade Nacional de Comunicações) regulations and their amateur radio license conditions.
