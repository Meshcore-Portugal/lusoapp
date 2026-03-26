# MeshCore PT — Aplicacao Companion para a Comunidade Portuguesa MeshCore

**MeshCore PT (MCAPPPT)** e uma aplicacao companion Flutter para radios [MeshCore](https://meshcore.net), criada por e para a comunidade portuguesa de radioamadores e redes mesh.

## Funcionalidades

- **Mensagens de Canal** — Enviar e receber mensagens nos canais MeshCore
- **Chat Privado** — Mensagens 1:1 encriptadas ponto-a-ponto via Ed25519/X25519
- **Configuracao do Radio** — Controlo total dos parametros LoRa (frequencia, largura de banda, SF, CR, potencia TX)
- **Gestao de Contactos** — Visualizar e gerir nos mesh descobertos (chat, repetidores, salas, sensores)
- **Ligacao BLE** — Ligar a radios MeshCore ESP32 e nRF52 via Bluetooth Low Energy
- **Ligacao Serie** — Ligar via USB OTG serie (115200 8N1)
- **Predefinicoes EU868** — Predefinicoes rapidas de radio em conformidade com regulamentos portugueses/UE
- **Interface em Portugues** — Interface completa em Portugues (Portugal)

## Inicio Rapido

### Pre-requisitos

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.29.0
- Android Studio ou VS Code com extensoes Flutter
- Um radio MeshCore (baseado em ESP32 ou nRF52)

### Compilar e Executar

```bash
# Clonar o repositorio
git clone <repo-url> mcapppt
cd mcapppt

# Obter dependencias
flutter pub get

# Executar no dispositivo ligado
flutter run

# Compilar APK de release
flutter build apk --release
```

### Plataformas Suportadas

| Plataforma | Transporte | Estado |
|------------|------------|--------|
| Android    | BLE + Serie | Alvo principal |
| iOS        | BLE | Planeado |
| Windows    | Serie | Planeado |
| Linux      | Serie | Planeado |

## Arquitectura

```
lib/
├── main.dart                    # Ponto de entrada da aplicacao
├── protocol/                    # Implementacao do protocolo MeshCore
│   ├── kiss.dart                # Enquadramento KISS TNC
│   ├── commands.dart            # Constantes de comandos/respostas
│   ├── models.dart              # Modelos de dados (Contacto, Mensagem, ConfigRadio)
│   ├── companion_encoder.dart   # Codificador de frames App→Radio
│   └── companion_decoder.dart   # Descodificador de frames Radio→App
├── transport/                   # Camada de comunicacao
│   ├── radio_transport.dart     # Interface abstracta de transporte
│   ├── ble_transport.dart       # Transporte BLE (Nordic UART)
│   └── serial_transport.dart    # Transporte Serie USB
├── services/
│   └── radio_service.dart       # Coordenador de comunicacao radio de alto nivel
├── providers/
│   └── radio_providers.dart     # Gestao de estado Riverpod
└── ui/
    ├── theme.dart               # Tema Material 3 escuro/claro
    ├── router.dart              # Navegacao GoRouter
    └── screens/
        ├── connect_screen.dart      # Procura e ligacao a dispositivos
        ├── home_screen.dart         # Shell principal com navegacao inferior
        ├── channel_chat_screen.dart # Mensagens de canal
        ├── private_chat_screen.dart # Chat privado 1:1
        ├── contacts_screen.dart     # Lista de contactos
        ├── radio_config_screen.dart # Configuracao LoRa
        └── settings_screen.dart     # Definicoes da aplicacao
```

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

## Licenca

Licenca MIT — consulte [LICENSE](LICENSE) para detalhes.
