"""Inspeciona o Data Product fct_billed_appointments gerado pelo dbt."""

import sys
from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "analytics.duckdb"
MART = "main.fct_billed_appointments"


def main() -> None:
    # Console do Windows (cp1252) não suporta os caracteres de borda das tabelas do DuckDB
    sys.stdout.reconfigure(encoding="utf-8")
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        tables = [r[0] for r in con.execute("select table_name from information_schema.tables order by 1").fetchall()]
        print(f"Tabelas disponíveis: {tables}\n")

        total, billed, denied, copay, net, receivable = con.execute(f"""
            select count(*), sum(billed_amount), sum(denied_amount), sum(copay_amount),
                   sum(net_amount), sum(plan_receivable)
            from {MART}
        """).fetchone()
        print("=== KPIs do Faturamento (atendimentos COMPLETED) ===")
        print(f"Atendimentos realizados : {total}")
        print(f"Valor bruto faturado    : R$ {billed:,.2f}")
        print(f"Glosas                  : R$ {denied:,.2f} ({denied / billed:.1%})")
        print(f"Coparticipação          : R$ {copay:,.2f}")
        print(f"Valor líquido           : R$ {net:,.2f}")
        print(f"A receber das pagadoras : R$ {receivable:,.2f}\n")

        print("=== Por especialidade ===")
        print(con.sql(f"""
            select specialty, count(*) as atendimentos,
                   round(sum(net_amount), 2) as valor_liquido
            from {MART} group by 1 order by 3 desc
        """))

        print("=== Por fonte pagadora ===")
        print(con.sql(f"""
            select health_plan, count(*) as atendimentos,
                   round(sum(denied_amount), 2) as glosas,
                   round(sum(plan_receivable), 2) as a_receber
            from {MART} group by 1 order by 4 desc
        """))

        print("=== Amostra (5 linhas) ===")
        print(con.sql(f"select * from {MART} order by appointment_at limit 5"))


if __name__ == "__main__":
    main()
