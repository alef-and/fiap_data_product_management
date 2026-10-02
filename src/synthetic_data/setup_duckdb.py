"""Gera a base sintética de atendimentos médicos em data/analytics.duckdb."""

import random
from datetime import datetime, timedelta
from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "analytics.duckdb"
N_RECORDS = 1000
SEED = 42

SPECIALTIES = {
    "CARDIOLOGIA": (250.0, 1800.0),
    "PEDIATRIA": (150.0, 600.0),
    "ORTOPEDIA": (200.0, 2500.0),
    "DERMATOLOGIA": (180.0, 900.0),
    "GINECOLOGIA": (180.0, 1200.0),
    "NEUROLOGIA": (300.0, 3000.0),
    "CLINICA_GERAL": (120.0, 400.0),
}
PROCEDURES = ["10101012", "10101039", "40301630", "40304361", "40901122", "41001010", "20104090"] # Códigos no padrão TUSS (Fictícios)
HEALTH_PLANS = ["SUS", "PARTICULAR", "VIDA_PLENA", "SAUDE_MAIS", "BEM_ESTAR"]
CARE_TYPES = ["ELECTIVE", "EMERGENCY"]
STATUSES = ["COMPLETED", "CANCELLED", "NO_SHOW", "DENIED"]
STATUS_WEIGHTS = [0.75, 0.10, 0.08, 0.07]


def generate_rows(n: int) -> list[tuple]:
    rng = random.Random(SEED)
    start = datetime(2026, 1, 1)
    rows = []
    for i in range(1, n + 1):
        specialty = rng.choice(list(SPECIALTIES))
        low, high = SPECIALTIES[specialty]
        health_plan = rng.choice(HEALTH_PLANS)
        status = rng.choices(STATUSES, weights=STATUS_WEIGHTS)[0]

        billed = round(rng.uniform(low, high), 2)
        # Glosa só ocorre em convênios; SUS/PARTICULAR não sofrem glosa
        denied = 0.0
        if health_plan not in ("SUS", "PARTICULAR") and rng.random() < 0.2:
            denied = round(billed * rng.uniform(0.05, 0.4), 2)
        if status == "DENIED":
            denied = billed
        copay = round(billed * 0.3, 2) if health_plan in ("VIDA_PLENA", "SAUDE_MAIS") else 0.0

        rows.append((
            f"ATD-{i:06d}",
            f"PAC-{rng.randint(1, 400):05d}",
            f"MED-{rng.randint(1, 60):04d}",
            specialty,
            rng.choice(PROCEDURES),
            health_plan,
            rng.choices(CARE_TYPES, weights=[0.8, 0.2])[0],
            status,
            billed,
            denied,
            copay,
            start + timedelta(minutes=rng.randint(0, 270 * 24 * 60)),
        ))
    return rows


def main() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    rows = generate_rows(N_RECORDS)

    with duckdb.connect(str(DB_PATH)) as con:
        con.execute("drop table if exists main.appointments")
        con.execute("""
            create table main.appointments (
                appointment_id  varchar,
                patient_id      varchar,
                provider_id     varchar,
                specialty       varchar,
                procedure_code  varchar,
                health_plan     varchar,
                care_type       varchar,
                status          varchar,
                billed_amount   double,
                denied_amount   double,
                copay_amount    double,
                appointment_at  timestamp
            )
        """)
        con.executemany("insert into main.appointments values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", rows)
        total = con.execute("select count(*) from main.appointments").fetchone()[0]

    print(f"[OK] Database analytics.duckdb initialized with {total} records.")
    print("[OK] Setup completed successfully!")


if __name__ == "__main__":
    main()
