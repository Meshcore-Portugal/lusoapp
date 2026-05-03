# MeshCore PT — Aplicacao Companion para a Comunidade Portuguesa MeshCore

**MeshCore PT (lusoapp)** e uma aplicacao companion Flutter para radios [MeshCore](https://meshcore.net), criada por e para a comunidade portuguesa de radioamadores e redes mesh.

## Funcionalidades

- **Mensagens de Canal** — Enviar e receber mensagens nos canais MeshCore
- **Chat Privado** — Mensagens 1:1 encriptadas ponto-a-ponto via Ed25519/X25519
- **Configuracao do Radio** — Controlo total dos parametros LoRa (frequencia, largura de banda, SF, CR, potencia TX)
- **Gestao de Contactos** — Visualizar e gerir nos mesh descobertos (chat, repetidores, salas, sensores)
- **Ligacao BLE** — Ligar a radios MeshCore ESP32 e nRF52 via Bluetooth Low Energy
- **Ligacao Serie** — Ligar via USB OTG serie (115200 8N1)
- **Predefinicoes EU868** — Predefinicoes rapidas de radio em conformidade com regulamentos portugueses/UE
- **Interface em Portugues** — Interface completa em Portugues (Portugal)
- **Vista de Mapa** — Mapa GPS em tempo real de todos os contactos e nos mesh (OpenStreetMap, sem necessidade de chave API)
- **Mapa Offline** — Cache de tiles via `flutter_map_tile_caching`; os tiles sao guardados automaticamente enquanto navega no mapa com ligacao e servidos a partir do disco quando offline

> **Nota sobre cache offline do mapa:** A cache de tiles e exclusivamente por navegacao — os tiles sao guardados a medida que explora o mapa com ligacao e reproduzidos quando offline. Nao existe funcionalidade de pre-descarregamento em massa de uma area. Isto e intencional: a [politica](https://operations.osmfoundation.org/policies/tiles/) do servidor de tiles da OSM proibe o pre-descarregamento em massa de regioes.

## Inicio Rapido

### Pre-requisitos

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.29.0
- Android Studio ou VS Code com extensoes Flutter
- Um radio MeshCore (baseado em ESP32 ou nRF52)

### Compilar e Executar

```bash
# Clonar o repositorio
git clone <repo-url> lusoapp
cd lusoapp

# Obter dependencias
flutter pub get

# Executar no dispositivo ligado
flutter run

# Compilar APK de release
flutter build apk --release
```

### Plataformas Suportadas

| Plataforma | Transporte  | Estado         |
| ---------- | ----------- | -------------- |
| Android    | BLE + Serie | Alvo principal |
| iOS        | BLE         | Planeado       |
| Windows    | Serie       | Planeado       |
| Linux      | Serie       | Planeado       |

## Arquitectura

```
lib/
├── main.dart                    # Ponto de entrada da aplicacao
├── protocol/                    # Implementacao do protocolo MeshCore
│   ├── kiss.dart                # Enquadramento KISS TNC
│   ├── commands.dart            # Constantes de comandos/respostas
│   ├── models.dart              # Modelos de dados (Contacto, Mensagem, ConfigRadio)
│   ├── companion_encoder.dart   # Codificador de frames App→Radio
│   ├── companion_decoder.dart   # Descodificador de frames Radio→App
│   └── companion_responses.dart # Classes DTO de respostas/pushes
├── transport/                   # Camada de comunicacao
│   ├── radio_transport.dart     # Interface abstracta de transporte
│   ├── ble_transport.dart       # Transporte BLE (Nordic UART)
│   └── serial_transport.dart    # Transporte Serie USB
├── services/
│   └── radio_service.dart       # Coordenador de comunicacao radio de alto nivel
├── providers/
│   ├── radio_providers.dart     # Gestao de estado Riverpod (ponto de entrada)
│   └── parts/                   # Notifiers divididos por dominio
│       ├── connection_notifier.dart
│       ├── messages_notifier.dart
│       └── advert_auto_add.dart
└── ui/
    ├── theme.dart               # Tema Material 3 escuro/claro
    ├── router.dart              # Navegacao GoRouter
    ├── screens/                 # Ecras principais (chat, contactos, definicoes…)
    │   └── parts/               # Widgets parciais por ecra
    └── apps/                    # "Apps" autonomas lancadas a partir do separador Apps
        ├── plan333/
        ├── telemetry/
        ├── topology/
        ├── rx_log/
        └── noise_floor/
```

### Adicionar uma nova app

Cada entrada do separador **Apps** vive na sua propria pasta em
`lib/ui/apps/<nome>/`, para que possa crescer sem inchar os ecras partilhados.
Para adicionar uma:

1. **Criar a pasta e o ecra** — `lib/ui/apps/<nome>/<nome>_screen.dart`.
   Exponha um widget publico (ex.: `class MyAppScreen extends ConsumerWidget`).
   Sub-widgets opcionais ficam em `lib/ui/apps/<nome>/parts/` como ficheiros
   `part` de Dart (`part of '../<nome>_screen.dart';`).
2. **Registar a rota** em [`lib/ui/router.dart`](lib/ui/router.dart):
   ```dart
   import 'apps/<nome>/<nome>_screen.dart';
   // …
   GoRoute(path: '/apps/<nome>', builder: (_, _) => const MyAppScreen()),
   ```
3. **Adicionar o tile do lancador** em [`lib/ui/screens/apps_screen.dart`](lib/ui/screens/apps_screen.dart)
   acrescentando um `_AppEntry` a lista `_apps` com `route: '/apps/<nome>'`.
4. **(Opcional) traduzir** quaisquer strings visiveis ao utilizador atraves dos
   ficheiros ARB em `lib/l10n/`.

E pronto: a app aparece na grelha Apps, e acessivel por deep link, e mantem os
seus widgets, helpers e testes isolados do resto da base de codigo.

## Suporte de Protocolo

A aplicacao implementa o **Protocolo Companion Radio MeshCore v3**:

- Todos os comandos App→Radio (APP_START, SEND_MSG, SEND_CHAN_MSG, GET_CONTACTS, SET_RADIO_PARAMS, etc.)
- Todas as respostas Radio→App (SELF_INFO, CONTACT, CHANNEL_MSG_RECV_V3, etc.)
- Notificacoes push nao solicitadas (ADVERT, MSG_WAITING, SEND_CONFIRMED, etc.)
- BLE: Nordic UART Service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`)
- Serie: 115200 baud, 8N1, DTR+RTS

## Informacao Regulamentar

Os parametros LoRa predefinidos estao em conformidade com os regulamentos SRD EU868:
- Frequencia: 869.618 MHz
- Largura de banda: 62.5 kHz
- Potencia TX: 14 dBm ERP maximo
- Ciclo de trabalho: Os utilizadores devem respeitar os limites de 10%

Os utilizadores sao responsaveis pela conformidade com os regulamentos da ANACOM e as condicoes da licenca de radioamador.

## Contribuir

Contribuicoes sao bem-vindas! Consulte o [ROADMAP.md](ROADMAP.md) para funcionalidades planeadas e a direcao do projeto.

## Presets de Funcionalidades para Release

Para presets de ativação/desativação de apps no build e overrides por funcionalidade, consulte:
- [docs/feature-toggles.pt-PT.md](docs/feature-toggles.pt-PT.md) (Português - Portugal)
- [docs/feature-toggles.md](docs/feature-toggles.md) (English)

## Licenca

Licenca MIT — consulte [LICENSE](LICENSE) para detalhes.
