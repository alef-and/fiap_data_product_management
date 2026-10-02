"""Restaura a tabela bruta ao estado canônico (seed fixa), removendo qualquer anomalia injetada."""

import setup_duckdb

if __name__ == "__main__":
    setup_duckdb.main()
    print("[OK] Dados restaurados ao estado canônico.")
