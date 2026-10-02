"""Inspeciona os resultados de qualidade: último dbt build/test e checagens de integridade no DuckDB."""

import json
import sys
from collections import Counter
from pathlib import Path

import duckdb

ROOT_DIR = Path(__file__).resolve().parents[2]
DB_PATH = ROOT_DIR / "data" / "analytics.duckdb"
RUN_RESULTS = ROOT_DIR / "src" / "dbt" / "target" / "run_results.json"
MART = "main.fct_billed_appointments"
STG = "main.stg_appointments"


def test_category(unique_id: str) -> str:
    name = unique_id.split(".")[2]
    if name.startswith("assert_"):
        return "Singular (SQL)"
    if name.startswith("dbt_expectations_"):
        return "dbt-expectations"
    return "Nativo (genérico)"


def print_run_results() -> None:
    print("=== Último dbt build/test (src/dbt/target/run_results.json) ===")
    if not RUN_RESULTS.exists():
        print("Nenhum resultado encontrado. Execute 'dbt build' antes.\n")
        return

    results = [r for r in json.loads(RUN_RESULTS.read_text(encoding="utf-8"))["results"]
               if r["unique_id"].startswith("test.")]
    by_category = Counter((test_category(r["unique_id"]), r["status"]) for r in results)
    for category in ("Nativo (genérico)", "dbt-expectations", "Singular (SQL)"):
        statuses = {s: n for (c, s), n in by_category.items() if c == category}
        print(f"{category:<20}: {statuses or '-'}")

    failures = [r["unique_id"].split(".")[2] for r in results if r["status"] in ("fail", "error")]
    print(f"Testes com falha     : {len(failures)}")
    for name in failures:
        print(f"  - {name}")
    print()


def main() -> None:
    # Console do Windows (cp1252) não suporta os caracteres de borda das tabelas do DuckDB
    sys.stdout.reconfigure(encoding="utf-8")
    print_run_results()

    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        def scalar(sql: str) -> int:
            return con.execute(sql).fetchone()[0]

        print("=== Checagens de integridade no Data Product ===")
        print(f"Registros no Mart                       : {scalar(f'select count(*) from {MART}')}")
        print(f"IDs duplicados                          : {scalar(f'select count(*) - count(distinct appointment_id) from {MART}')}")
        print(f"IDs/pacientes/médicos nulos             : {scalar(f'select count(*) from {MART} where appointment_id is null or patient_id is null or provider_id is null')}")
        print(f"Violações contábeis (glosa+copay > bruto): {scalar(f'select count(*) from {MART} where denied_amount + copay_amount > billed_amount + 0.01')}")
        print(f"Valores a receber negativos             : {scalar(f'select count(*) from {MART} where plan_receivable < 0')}")
        print(f"COMPLETED no Staging ausentes no Mart   : {scalar(f'''
            select count(*) from {STG} s
            left join {MART} m using (appointment_id)
            where s.status = 'COMPLETED' and m.appointment_id is null''')}")
        print()

        print("=== Taxa de glosa por fonte pagadora ===")
        print(con.sql(f"""
            select health_plan,
                   round(sum(billed_amount), 2) as faturado,
                   round(sum(denied_amount), 2) as glosado,
                   round(100 * sum(denied_amount) / sum(billed_amount), 2) as taxa_glosa_pct
            from {MART} group by 1 order by 4 desc
        """))


if __name__ == "__main__":
    main()
