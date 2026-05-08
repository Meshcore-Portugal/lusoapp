# Feature Toggles e Presets de Release

Este projeto suporta toggles de funcionalidades no momento do build, usando valores Flutter `--dart-define`.

A lógica de toggles está centralizada em:
- `lib/config/feature_toggles.dart`

## Início Rápido

Para a maioria das releases, use apenas um preset:
- `FEATURE_PRESET=legacy` (valor por defeito, se for omitido)
- `FEATURE_PRESET=minimal`
- `FEATURE_PRESET=full`

### Presets PowerShell

- Minimal:

```powershell
./scripts/build_release_minimal.ps1
```

- Full:

```powershell
./scripts/build_release_full.ps1
```

- Compilar AAB em vez de APK:

```powershell
./scripts/build_release_minimal.ps1 -Target appbundle
./scripts/build_release_full.ps1 -Target appbundle
```

- Dry run:

```powershell
./scripts/build_release_minimal.ps1 -DryRun
./scripts/build_release_full.ps1 -DryRun
```

### Presets Bash (Linux/CI)

- Minimal:

```bash
bash ./scripts/build_release_minimal.sh
```

- Full:

```bash
bash ./scripts/build_release_full.sh
```

- Compilar AAB em vez de APK:

```bash
bash ./scripts/build_release_minimal.sh appbundle
bash ./scripts/build_release_full.sh appbundle
```

- Dry run:

```bash
bash ./scripts/build_release_minimal.sh --dry-run
bash ./scripts/build_release_full.sh --dry-run
```

## Definição dos Presets

### `legacy` (por defeito)
- Topology: desligado
- Plan333: ligado
- Telemetry: ligado
- RX Log: ligado
- Noise Floor: ligado
- Data Export: ligado
- Event: desligado

### `minimal`
- Topology: desligado
- Plan333: ligado
- Telemetry: ligado
- RX Log: desligado
- Noise Floor: desligado
- Data Export: desligado
- Event: desligado

### `full`
- Topology: ligado
- Plan333: ligado
- Telemetry: ligado
- RX Log: ligado
- Noise Floor: ligado
- Data Export: ligado
- Event: ligado

## Overrides por App

As defines por app sobrepõem-se sempre aos valores do preset.

Flags disponíveis:
- `FEATURE_APP_TOPOLOGY`
- `FEATURE_APP_PLAN333`
- `FEATURE_APP_TELEMETRY`
- `FEATURE_APP_RXLOG`
- `FEATURE_APP_NOISEFLOOR`
- `FEATURE_APP_DATAEXPORT`
- `FEATURE_APP_EVENT`

Exemplo: preset minimal, mas com RX Log forçado para ligado:

```bash
flutter build apk --release \
  --dart-define=FEATURE_PRESET=minimal \
  --dart-define=FEATURE_APP_RXLOG=true
```

Exemplo (PowerShell):

```powershell
flutter build apk --release `
  --dart-define=FEATURE_PRESET=minimal `
  --dart-define=FEATURE_APP_RXLOG=true
```

## Efeito em Runtime

Quando uma funcionalidade está desligada:
- O respetivo tile fica oculto no ecrã Apps.
- A respetiva rota não é registada no router.

Isto significa que os módulos desativados ficam escondidos na UI e bloqueados para deep-link/navegação direta.

## Fluxo de Release Recomendado

1. Escolher o preset (`minimal` ou `full`).
2. Executar o script em modo dry-run e validar as flags.
3. Compilar APK/AAB.
4. Fazer um sanity-check ao separador Apps na build de release.
5. Se necessário, adicionar um ou mais overrides por app.
