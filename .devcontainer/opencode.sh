#!/bin/bash
set -euo pipefail

curl -fsSL https://opencode.ai/install | bash
npx --yes get-shit-done-cc@latest --opencode --global