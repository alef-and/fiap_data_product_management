#!/usr/bin/env bash
# Demonstra o DAG Circuit Breaker: dados corrompidos na origem sao bloqueados antes de chegar ao consumidor.
# Uso (a partir da raiz): bash scripts/run_circuit_breaker.sh

set -uo pipefail

# Todos os caminhos (dbt, Soda, DuckDB) sao relativos a raiz do repositorio
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_BIN="$ROOT_DIR/.venv/bin"
PYTHON="$VENV_BIN/python"
DBT="$VENV_BIN/dbt"
SODA="$VENV_BIN/soda"
DBT_DIRS=(--project-dir src/dbt --profiles-dir src/dbt)
SODA_ARGS=(scan -d analytics -c src/quality_gate/configuration.yml src/quality_gate/checks.yml)
SNAPSHOT_QUERY="import duckdb; c=duckdb.connect('data/analytics.duckdb', read_only=True); r=c.execute('select count(*), round(sum(net_amount), 2) from main.fct_billed_appointments').fetchone(); print(f'{r[0]} linhas | net_amount total = {r[1]}')"

if [[ ! -x "$PYTHON" || ! -x "$DBT" || ! -x "$SODA" ]]; then
    echo "[FALHA] Ambiente virtual nao encontrado em $VENV_BIN." >&2
    echo "        Crie-o na raiz: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
    exit 1
fi

cd "$ROOT_DIR"

title() { printf '\n\033[36m==================== %s ====================\033[0m\n' "$1"; }
stop_demo() { printf '\033[31m[FALHA NA DEMO] %s\033[0m\n' "$1" >&2; exit 1; }

expect_success() {
    local name="$1"; shift
    title "$name"
    local code=0
    "$@" || code=$?
    [[ $code -eq 0 ]] || stop_demo "$name deveria passar (exit code $code)."
}

expect_failure() {
    local name="$1"; shift
    title "$name"
    local code=0
    "$@" || code=$?
    [[ $code -ne 0 ]] || stop_demo "$name deveria ter bloqueado a esteira."
    printf '\033[33m[BLOQUEADO] %s interrompeu a esteira (exit code %s), como esperado.\033[0m\n' "$name" "$code"
}

# 1. Estado saudavel
expect_success 'Passo 1: Base sintetica limpa'        "$PYTHON" src/synthetic_data/setup_duckdb.py
expect_success 'Passo 2: dbt deps'                     "$DBT" deps "${DBT_DIRS[@]}"
expect_success 'Passo 3: dbt build (estado saudavel)'  "$DBT" build "${DBT_DIRS[@]}"
BEFORE="$("$PYTHON" -c "$SNAPSHOT_QUERY")"
printf '\033[32mMart antes do incidente: %s\033[0m\n' "$BEFORE"

# 2. Incidente na origem
expect_success 'Passo 4: Injecao de dados corrompidos' "$PYTHON" src/synthetic_data/inject_anomaly.py

# 3. Gate 1: Soda Core na ingestao
expect_failure 'Passo 5: Gate 1 - Soda Core (ingestao)' "$SODA" "${SODA_ARGS[@]}"

# 4. Gate 2: testes do dbt (simulando que o Gate 1 foi ignorado)
expect_failure 'Passo 6: Gate 2 - dbt build (Circuit Breaker)' "$DBT" build "${DBT_DIRS[@]}"

# 5. Consumidor protegido
title 'Passo 7: Verificacao do Mart de consumo'
AFTER="$("$PYTHON" -c "$SNAPSHOT_QUERY")"
echo "Mart antes : $BEFORE"
echo "Mart depois: $AFTER"
[[ "$BEFORE" == "$AFTER" ]] || stop_demo 'O Mart foi alterado pelos dados corrompidos.'
printf '\033[32m[PROTEGIDO] O Mart manteve os ultimos dados validos.\033[0m\n'

# 6. Restauracao
expect_success 'Passo 8: Restauracao dos dados'      "$PYTHON" src/synthetic_data/restore_data.py
expect_success 'Passo 9: Gate 1 - Soda Core (verde)'  "$SODA" "${SODA_ARGS[@]}"
expect_success 'Passo 10: Gate 2 - dbt build (verde)' "$DBT" build "${DBT_DIRS[@]}"

printf '\n\033[32m[OK] Circuit Breaker demonstrado com sucesso: dados corrompidos bloqueados e consumidor protegido.\033[0m\n'
