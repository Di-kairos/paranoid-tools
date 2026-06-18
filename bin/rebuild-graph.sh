#!/usr/bin/env bash
# Пересобрать cross-repo граф экосистемы Paranoid Tools: мерджит графы всех
# инструментов (<tool>/graphify-out/graph.json) в один merged-graph.json.
# Запускать из корня paranoid-tools/. Требует graphify в PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Собрать список существующих графов инструментов.
graphs=()
for g in */graphify-out/graph.json; do
  [[ -f "$g" ]] && graphs+=("$g")
done

if [[ "${#graphs[@]}" -eq 0 ]]; then
  echo "Нет графов инструментов. Сначала: graphify update <tool>" >&2
  exit 1
fi

mkdir -p graphify-out
if [[ "${#graphs[@]}" -eq 1 ]]; then
  # merge-graphs требует ≥2 входов: с одним тулом просто копируем его граф.
  cp "${graphs[0]}" graphify-out/merged-graph.json
  echo "Один инструмент (${graphs[0]}) → скопирован в graphify-out/merged-graph.json"
  echo "Cross-repo связи появятся со 2-го инструмента."
else
  graphify merge-graphs "${graphs[@]}" --out graphify-out/merged-graph.json
  echo "Слито графов: ${#graphs[@]} → graphify-out/merged-graph.json"
fi
