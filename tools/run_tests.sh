#!/usr/bin/env bash
# Führt alle automatischen Prüfungen aus und baut die Place-Datei.
# Voraussetzungen: Rust (cargo), Python 3, Rojo 7 und Selene im PATH.
#   cargo install rojo selene
set -euo pipefail
cd "$(dirname "$0")/.."

RUNNER=tools/luau-runner/target/release/luau-runner
if [ ! -x "$RUNNER" ]; then
	echo "== Baue luau-runner (einmalig)"
	(cd tools/luau-runner && cargo build --release --quiet)
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== 1/6 Luau-Syntax (echter Luau-Compiler)"
find src -name '*.luau' -print0 | xargs -0 "$RUNNER"

echo "== 2/6 Selene-Linter"
selene src

echo "== 3/6 Querverweise zwischen Modulen"
python3 tools/check_crossrefs.py

echo "== 4/6 Strecken-Prüfung (alle Maps bauen + Lücken/Anker/Checkpoints)"
python3 tools/gen_tree.py "$TMP/tree.luau" > /dev/null
"$RUNNER" --run tools/test/maps_test.luau "$PWD" "$TMP/tree.luau" | tail -n 3

echo "== 5/6 End-to-End-Simulation (Server + Client im Mock)"
"$RUNNER" --run tools/test/server_test.luau "$PWD" "$TMP/tree.luau" | grep -E "Ergebnis|✗|RUN"

echo "== 6/6 Place-Datei bauen"
mkdir -p build
rojo build default.project.json -o build/VelocityRush.rbxlx
echo "Fertig: build/VelocityRush.rbxlx"
