"""Simula um incidente na origem: injeta atendimentos corrompidos na tabela bruta main.appointments."""

from datetime import datetime
from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "analytics.duckdb"

# (appointment_id, patient_id, provider_id, specialty, procedure_code, health_plan,
#  care_type, status, billed_amount, denied_amount, copay_amount, appointment_at)
CORRUPTED_ROWS = [
    (None, "PAC-00001", "MED-0001", "CARDIOLOGIA", "10101012", "SUS", "ELECTIVE", "COMPLETED", 350.0, 0.0, 0.0, datetime(2026, 9, 1, 10)),
    ("ATD-000001", "PAC-00002", "MED-0002", "PEDIATRIA", "10101012", "SUS", "ELECTIVE", "COMPLETED", 200.0, 0.0, 0.0, datetime(2026, 9, 1, 11)),
    ("ATD-900001", "PAC-00003", "MED-0003", "ORTOPEDIA", "40301630", "SUS", "EMERGENCY", "COMPLETED", -999.50, 0.0, 0.0, datetime(2026, 9, 1, 12)),
    ("ATD-900002", "PAC-00004", "MED-0004", "NEUROLOGIA", "40901122", "SUS", "ELECTIVE", "CORRUPTED_STATUS", 800.0, 0.0, 0.0, datetime(2026, 9, 1, 13)),
    ("ATD-900003", "PAC-00005", "MED-0005", "DERMATOLOGIA", "10101039", "PLANO_FANTASMA", "ELECTIVE", "COMPLETED", 300.0, 450.0, 0.0, datetime(2026, 9, 1, 14)),
]


def main() -> None:
    with duckdb.connect(str(DB_PATH)) as con:
        con.executemany("insert into main.appointments values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", CORRUPTED_ROWS)
        total = con.execute("select count(*) from main.appointments").fetchone()[0]

    print(f"[ANOMALIA] {len(CORRUPTED_ROWS)} registros corrompidos injetados em main.appointments (total: {total}).")
    print("  - appointment_id nulo")
    print("  - appointment_id duplicado (ATD-000001)")
    print("  - billed_amount negativo (-999.50)")
    print("  - status inválido (CORRUPTED_STATUS)")
    print("  - convênio inexistente (PLANO_FANTASMA) com glosa maior que o valor faturado")


if __name__ == "__main__":
    main()
