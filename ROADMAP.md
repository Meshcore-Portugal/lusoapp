# lusoapp — MeshCore Companion App Portugal

## Roadmap

### Phase 1 — Foundation (Complete: v0.1.x)

**Goal:** Working serial & BLE connection with basic messaging.

- [x] Project scaffolding (Flutter, Riverpod, GoRouter)
- [x] MeshCore Companion Protocol implementation
  - [x] KISS framing encoder/decoder (full byte-stuffing, streaming accumulator)
  - [x] Companion frame encoder (App → Radio) — 20+ methods, all v3 commands
  - [x] Companion frame decoder (Radio → App) — 30+ sealed response types, v2+v3
  - [x] Full command/response/push type definitions (32 cmd, 18 resp, 16 push codes)
- [x] Transport layer
  - [x] Abstract `RadioTransport` interface
  - [x] BLE transport (Nordic UART service, MTU negotiation, web workaround)
  - [x] Serial/USB OTG transport (flutter_libserialport, 115200 8N1)
  - [x] KISS TNC mode over serial (decorator transport)
  - [x] Device scanning and discovery
- [x] Core UI screens
  - [x] Device connection screen (BLE + Serial scan, 5-step progress)
  - [x] Channels list (unread badges, unread-first sort, refresh)
  - [x] Channel chat (send/receive channel messages)
  - [x] Private chat (1:1 encrypted messaging, trace route + reset path menu)
  - [x] Radio configuration (LoRa params, TX power, device info card)
  - [x] Contacts list (type-filter chips: Companheiros/Repetidores/Salas/Sensores)
  - [x] Settings screen (identity name edit, disconnect, public key display)
- [x] State management (Riverpod providers — full connection/data lifecycle)
- [x] Unread message tracking (per-channel and per-contact counts)
- [x] Battery and connection quality indicators (battery mV displayed)
- [x] GPS coordinates parsed and stored in Contact and SelfInfo models
- [x] Portuguese (Portugal) UI language (all screens hard-coded PT-PT)
- [x] Unit tests for protocol layer (22 tests: KISS + Companion encoder/decoder)
- [x] Integration tests for transport layer mocks (56 tests: MockRadioTransport, KissTransport, RadioService framed + BLE)

---

### Phase 2 — Persistence & Reliability (Complete: v0.2.x)

**Goal:** Message history, offline support, robust reconnection.

- [x] Local database (SharedPreferences-backed JSON store — `StorageService`)
  - [x] Message history persistence (per contact / per channel, capped at 500 msgs)
  - [x] Contact cache (survive app restarts — loaded on app start)
  - [x] Lazy message loading per chat screen (loaded on first open)
- [x] Auto-reconnect logic
  - [x] BLE reconnect on unexpected disconnect (`connectionLost` stream, single retry with 2 s backoff)
  - [ ] Serial reconnect on USB re-plug
- [x] Message delivery tracking
  - [x] Pending state (single tick) / confirmed state (double tick) in all chat UIs
  - [x] `SendConfirmedPush` wired to `confirmLastOutgoing()` in `MessagesNotifier`
  - [x] Repeater heard count on sent channel messages (loopback detection — "Ouvido por N repetidor(es)" label shown when relayed echo received back)
  - [ ] Retry on failure with exponential backoff
- [x] Background message sync (`SYNC_NEXT` loop — `MsgWaitingPush` triggers full offline queue drain)
- [x] Last connected device memory (saved to SharedPreferences + quick-connect card in ConnectScreen)
- [x] SNR display in chat (incoming messages show `SNR X.X dB`)
- [x] Channel create/edit UI (FAB + bottom sheet, index picker, name, secret, random key generation)
- [x] Contact add UI (FAB + bottom sheet, send advert, manual public key entry, `cmdAddUpdateContact`)
- [x] Contact delete UI (long-press on contact tile → confirm dialog → `cmdRemoveContact`)
- [x] QR code sharing and scanning
  - [x] Share own contact as QR code (Settings screen — `meshcore://contact/add?...`)
  - [x] Share any contact as QR code (QR icon on each contact tile)
  - [x] Share channel via QR code (QR icon on each channel tile — `meshcore://channel/add?...`)
  - [x] Scan QR to add contact (scanner in Add Contact sheet — parses and pre-fills form)
  - [x] Scan QR to add channel (scanner in Add/Edit Channel sheet — parses and pre-fills form)
- [x] Local OS notifications for new messages
  - [x] `flutter_local_notifications` — Android, iOS, macOS, Windows, Linux support
  - [x] `NotificationSettings` model with master enable, per-category toggles, background-only mode
  - [x] `NotificationService` singleton — inits Android channel, requests permission, fires alerts
  - [x] `NotificationSettingsNotifier` provider — persists settings via `StorageService`
  - [x] Notifications card in Settings screen — "Activar notificacoes", private, canal, background toggles
  - [x] `AppLifecycleObserver` — foreground detection for "only when background" mode
- [ ] Export/import contacts (command constants defined; binary encoder implemented, no import/export UI)

---

### Phase 3 — Advanced Features (Complete: v0.3.x)

**Goal:** Full companion app parity with richer UX.

- [x] Map view
  - [x] Display contacts with GPS coordinates (colour-coded markers by node type: blue=chat, orange=repeater, purple=room, teal=sensor)
  - [x] Self-location via phone GPS (`geolocator` — permission request, fallback to radio self-info coords)
  - [x] Own position marker (distinct style — primary-colour ring)
  - [x] Tap contact marker → bottom sheet (name, type, GPS coords, "Enviar mensagem" button)
  - [x] "Fit all" FAB — zoom to show all markers at once
  - [x] "Localizar" FAB — get device GPS and centre map
  - [x] OpenStreetMap tiles via `flutter_map` (no API key, OSM attribution shown)
  - [x] Empty-state hint card when no GPS data available
  - [x] Map rotation disabled (zoom/drag/pinch only)
  - [x] GPS centre button (fast-centre if position known, locate if not)
  - [x] Contact detail panel with full-width text (no truncation)
  - [x] Contact clustering — zoom-adaptive grouping, tap to expand or show list
  - [x] Path visualization between nodes (polyline overlay — trace hop GPS positions drawn in order)
- [x] Telemetry dashboard
  - [x] Battery history chart (sparkline with min/max labels, LiPo % estimate)
  - [x] Sensor data (CayenneLPP decode — 15 sensor types, `TelemetryPush` → `lib/protocol/cayenne_lpp.dart`)
  - [x] Network statistics (RX/TX/Error counters, heard-nodes counter, reset button)
  - [x] Wired as second tab inside Rádio screen ("Configuração" + "Telemetria")
- [x] Path tracing UI
  - [x] Visual hop-by-hop route display (`TraceDataPush` parsed in `lib/protocol/trace_parser.dart`; map PolylineLayer + info card; chat bottom sheet with SNR per hop)
  - [ ] Latency estimation
- [x] Contact favourites
  - [x] Star icon toggle on every contact tile (filled amber = favourite)
  - [x] "Favoritos" filter tab in contacts screen
  - [x] Persisted across sessions via `SharedPreferences` (`favorites_v1` key)
- [x] Repeater remote admin
  - [x] Login with admin password (`sendLogin 0x1A` → `LoginSuccessPush 0x85` / `LoginFailPush 0x86`)
  - [x] Request repeater stats (`cmdSendStatusReq 0x1B` → `pushStatusResponse 0x87`, `RepeaterStats` binary parser)
  - [x] Stats display: battery voltage, uptime, noise floor, RSSI, SNR, RX/TX packet counters, flood vs direct traffic, TX air time, RX air time, duplicates, error events
  - [x] Admin bottom sheet accessible via admin button on repeater contact tiles
- [x] Room server support
  - [x] Browse/join MeshCore rooms (`sendLogin` + `LoginSuccess/Fail` handled, join screen with password field)
  - [x] Room message list (full chat view, swipe-to-reply, SNR display, persistence via `contact_$hex6` store)
- [ ] Multi-radio support
  - [ ] Connect to multiple radios simultaneously
  - [ ] Radio selector in UI
- [x] Discover Contacts screen
  - [x] Lists all mesh-heard contacts (via advert timestamps) not yet in radio storage
  - [x] Search / filter, add-to-radio, send message, join room actions
- [x] Noise Floor / RSSI real-time chart
  - [x] Polls `CMD_GET_STATS` (radio stats) every 2 s
  - [x] Dual-series area chart (RSSI + Noise Floor, −120…−60 dBm range), toggle each series
- [x] RX Log screen + PCAP export
  - [x] Captures raw `0x88 LOG_RX` frames in a live scrolling list
  - [x] Exports captured frames as `.pcap` file via `share_plus`
- [x] Plan 3-3-3 emergency CQ tool
  - [x] Configurable station name, city, locality
  - [x] Auto-sends CQ on mesh channel during configured event window with live countdown
  - [x] Parses incoming CQ messages and displays heard-stations list
- [x] Android home screen widget
  - [x] Shows radio name, connection state, battery %, contact/channel counts, last-updated timestamp
  - [x] Updated on every state change via `WidgetService`
  - [x] Quick-action buttons: 📡 Send Advert · 💬 Chats · 🗺 Map · 🔌 Connect (via deep-link URIs handled by `HomeWidget.widgetClicked` stream)
  - [x] 🆘 SOS button broadcasts the user-flagged emergency canned message on channel 0
- [x] Canned messages library
  - [x] Persisted via `cannedMessagesProvider` (SharedPreferences); 8 ham/mesh defaults seeded on first launch (SOS, QRT, QRX, 73, CQ, OK, QTH?, ETA)
  - [x] Manage in Settings → Mensagens rápidas (add / edit / delete / reorder / reset, single emergency-flag enforced)
  - [x] Quick-pick ⚡ icon in private + channel chat composers inserts text into the input
- [x] User-controlled GPS sharing
  - [x] **Off by default** — user explicitly opts in via Settings → Partilha de GPS
  - [x] Three modes: `off` / `manual` (one-shot from Map FAB or Settings) / `auto` (configurable 1–60 min timer)
  - [x] Privacy precision chips: Exact (~1 m) · Rough (±100 m) · Vague (±1 km) — applied before pushing
  - [x] Pushes phone GPS via `CMD_SET_ADVERT_LATLON 0x0E` (`radioService.setLocation`) so the radio's outgoing adverts carry the location flag
  - [x] Toggling `off` automatically clears coords on the radio (sends 0,0 sentinel) and stops the timer
  - [x] Settings card shows live status badge (DESLIGADA / MANUAL / AUTOMÁTICA), last-shared timestamp + coords, and an explicit privacy disclaimer
  - [x] Map screen exposes a green "Partilhar agora" FAB **only when sharing is enabled**, never auto-prompting for location
  - [x] **Move-aware Auto mode** — configurable 0–1000 m threshold (default 50 m); skips redundant pushes when the phone hasn't moved, saving LoRa air-time
  - [x] **Home-screen widget badge** — green 📍 dot appears in the widget header whenever sharing is enabled, hidden otherwise
  - [x] **Interactive radio policy toggle** — Switch surfaces the radio's `adv_loc_policy` byte (parsed from `RESP_SELF_INFO` offset 44) and writes it via `CMD_SET_OTHER_PARAMS` (0x26), round-tripping `manual_add_contacts`, `telemetry_mode` and `multi_acks` unchanged so only the location policy is mutated
- [x] Per-contact map opt-in
  - [x] `mapHiddenContactsProvider` (SharedPreferences-backed Set of pubKey hex)
  - [x] Contact bottom sheet on the map exposes a "Mostrar no mapa" switch — user can hide any contact from the map even if their adverts include GPS
  - [x] Hidden contacts are filtered out of the marker layer, cluster, and fit-all bounds
- [x] Event Program screen (hidden)
  - [x] Hardcoded MeshCore PT summit schedule; route wired but tile disabled in Apps screen

---

### Phase 4 — Community & Polish (Current: v0.4.x)

**Goal:** Community features, localization, and release readiness.

- [x] Full i18n framework (ARB files generated, `app_localizations` wired via `context.l10n`)
  - [x] Portuguese (Portugal) — primary
  - [x] English — secondary
  - [x] Spanish — community contribution
- [ ] QR code sharing
  - [x] Share own contact via QR (Settings screen)
  - [x] Share any contact via QR (contact tile icon)
  - [x] Share channel via QR (channel tile icon)
  - [x] Scan QR to add contact
  - [x] Scan QR to add/configure channel
- [ ] Theme customization
  - [x] Light/dark mode toggle (System / Light / Dark via `themeModeProvider`, persisted to SharedPreferences; selectable in Settings → Appearance)
  - [x] Custom accent colors (`accentColorProvider` overrides Material `colorScheme.primary`; 16-swatch picker in Settings → Appearance with one-tap reset to brand orange)
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

- [x] Mesh topology viewer
  - [x] Visual network graph (interactive pan/zoom; concentric rings by hop distance; SNR-coded edges from trace history; tap-to-contact sheet)
  - [x] Node discovery timeline (contacts sorted by last-heard timestamp)
- [x] Repeater management
  - [x] View repeater status
  - [x] Configure repeater settings (if admin)
- [ ] Channel management
  - [x] Create/edit channels on radio (FAB + bottom sheet, Phase 2)
  - [ ] Channel encryption key rotation UI
- [ ] Firmware update over BLE/Serial
  - [ ] OTA firmware upload
  - [ ] Version check and notification
- [ ] Power management profiles
  - [ ] Low-power mode scheduling
  - [ ] TX power by time-of-day
- [x] Data export
  - [x] CSV export of contacts and messages
  - [x] KML export for map data
  - [x] Protocol log export for debugging (RX Log + PCAP — implemented in Phase 3)

---

### Phase 6 — Integration & Ecosystem (v1.0.x)

**Goal:** Production-ready release with ecosystem integration.

- [ ] Webhook/automation support
  - [ ] Incoming message webhooks
  - [ ] IFTTT/Home Assistant integration
- [ ] Widget support
  - [x] Android home screen widget (implemented in Phase 3)
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
│                   Flutter App                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  UI/UX   │  │ Providers│  │  Local DB     │  │
│  │ (Screens)│◄─┤(Riverpod)│◄─┤  (Isar)       │  │
│  └──────────┘  └────┬─────┘  └───────────────┘  │
│                     │                           │
│              ┌──────┴──────┐                    │
│              │RadioService │                    │
│              │(Coordinator)│                    │
│              └──────┬──────┘                    │
│                     │                           │
│           ┌─────────┴─────────┐                 │
│           │  Protocol Layer   │                 │
│           │ ┌───────┐ ┌─────┐ │                 │
│           │ │Encoder│ │Decod│ │                 │
│           │ └───────┘ └─────┘ │                 │
│           └─────────┬─────────┘                 │
│                     │                           │
│           ┌─────────┴─────────┐                 │
│           │  Transport Layer  │                 │
│           │ ┌─────┐ ┌──────┐  │                 │
│           │ │ BLE │ │Serial│  │                 │
│           │ └─────┘ └──────┘  │                 │
│           └───────────────────┘                 │
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
