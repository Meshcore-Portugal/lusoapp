# MeshCore PT — Companion App for the Portuguese MeshCore Community

**MeshCore PT (MCAPPPT)** is a Flutter companion app for [MeshCore](https://meshcore.net) radios, built by and for the Portuguese amateur radio and mesh networking community.

## Features

- **Channel Messaging** — Send and receive messages on MeshCore channels
- **Private Chat** — End-to-end encrypted 1:1 messaging via Ed25519/X25519
- **Radio Configuration** — Full LoRa parameter control (frequency, bandwidth, SF, CR, TX power)
- **Contact Management** — View and manage discovered mesh nodes (chat, repeaters, rooms, sensors)
- **BLE Connection** — Connect to ESP32 and nRF52 MeshCore radios via Bluetooth Low Energy
- **Serial Connection** — Connect via USB OTG serial (115200 8N1)
- **EU868 Presets** — Quick radio presets compliant with Portuguese/EU regulations
- **Portuguese UI** — Full Portuguese (Portugal) interface

## Quick Start

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.29.0
- Android Studio or VS Code with Flutter extensions
- A MeshCore radio (ESP32 or nRF52 based)

### Build & Run

```bash
# Clone the repository
git clone <repo-url> mcapppt
cd mcapppt

# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release
```

### Supported Platforms

| Platform | Transport | Status |
|----------|-----------|--------|
| Android  | BLE + Serial | Primary target |
| iOS      | BLE | Planned |
| Windows  | Serial | Planned |
| Linux    | Serial | Planned |

## Architecture

```
lib/
├── main.dart                    # App entry point
├── protocol/                    # MeshCore protocol implementation
│   ├── kiss.dart                # KISS TNC framing
│   ├── commands.dart            # Command/response constants
│   ├── models.dart              # Data models (Contact, Message, RadioConfig)
│   ├── companion_encoder.dart   # App→Radio frame encoder
│   └── companion_decoder.dart   # Radio→App frame decoder
├── transport/                   # Communication layer
│   ├── radio_transport.dart     # Abstract transport interface
│   ├── ble_transport.dart       # BLE (Nordic UART) transport
│   └── serial_transport.dart    # USB Serial transport
├── services/
│   └── radio_service.dart       # High-level radio communication coordinator
├── providers/
│   └── radio_providers.dart     # Riverpod state management
└── ui/
    ├── theme.dart               # Material 3 dark/light theme
    ├── router.dart              # GoRouter navigation
    └── screens/
        ├── connect_screen.dart      # Device scan & connect
        ├── home_screen.dart         # Main shell with bottom nav
        ├── channel_chat_screen.dart # Channel messaging
        ├── private_chat_screen.dart # 1:1 private chat
        ├── contacts_screen.dart     # Contact list
        ├── radio_config_screen.dart # LoRa configuration
        └── settings_screen.dart     # App settings
```

## Protocol Support

The app implements the **MeshCore Companion Radio Protocol v3**:

- All App→Radio commands (APP_START, SEND_MSG, SEND_CHAN_MSG, GET_CONTACTS, SET_RADIO_PARAMS, etc.)
- All Radio→App responses (SELF_INFO, CONTACT, CHANNEL_MSG_RECV_V3, etc.)
- Unsolicited push notifications (ADVERT, MSG_WAITING, SEND_CONFIRMED, etc.)
- BLE: Nordic UART Service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`)
- Serial: 115200 baud, 8N1, DTR+RTS

## Regulatory Information

Default LoRa parameters comply with EU868 SRD regulations:
- Frequency: 869.618 MHz
- Bandwidth: 62.5 kHz
- TX Power: 14 dBm ERP max
- Duty Cycle: Users must respect 10% limits

Users are responsible for compliance with ANACOM regulations and amateur radio licence conditions.

## Contributing

Contributions are welcome! Please see the [ROADMAP.md](ROADMAP.md) for planned features and the project direction.

## License

MIT License — see [LICENSE](LICENSE) for details.
