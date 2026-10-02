#!/usr/bin/env bash
# Executa a esteira completa do Data Product usando o ambiente virtual do projeto (Linux/macOS).
# Uso (a partir da raiz): bash scripts/run_pipeline.sh

set -euo pipefail

# Todos os caminhos (dbt, Soda, DuckDB) sao relativos a raiz do repositorio
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_BIN="$ROOT_DIR/.venv/bin"
PYTHON="$VENV_BIN/python"
DBT="$VENV_BIN/dbt"
SODA="$VENV_BIN/soda"
DBT_DIRS=(--project-dir src/dbt --profiles-dir src/dbt)

if [[ ! -x "$PYTHON" || ! -x "$DBT" || ! -x "$SODA" ]]; then
    echo "[FALHA] Ambiente virtual nao encontrado em $VENV_BIN." >&2
    echo "        Crie-o na raiz: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
    exit 1
fi

cd "$ROOT_DIR"

step() {
    local title="$1"; shift
    printf '\n\033[36m==================== %s ====================\033[0m\n' "$title"
    local code=0
    "$@" || code=$?
    if [[ $code -ne 0 ]]; then
        printf '\033[31m[FALHA] %s (exit code %s). Esteira interrompida.\033[0m\n' "$title" "$code" >&2
        exit "$code"
    fi
}

step 'Passo 1: Base sintetica DuckDB'      "$PYTHON" src/synthetic_data/setup_duckdb.py
step 'Passo 2: Quality Gate (Soda Core)'   "$SODA" scan -d analytics -c src/quality_gate/configuration.yml src/quality_gate/checks.yml
step 'Passo 3: dbt deps'                   "$DBT" deps "${DBT_DIRS[@]}"
step 'Passo 4: dbt debug'                  "$DBT" debug "${DBT_DIRS[@]}"
step 'Passo 5: dbt build (modelos+testes)' "$DBT" build "${DBT_DIRS[@]}"
step 'Passo 6: Inspecao do Mart'           "$PYTHON" src/inspection/query_mart.py
step 'Passo 7: Resultados de qualidade'    "$PYTHON" src/inspection/query_test_results.py

printf '\n\033[32m[OK] Esteira executada com sucesso!\033[0m\n'
