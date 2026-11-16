"""ELT batch sederhana: OLTP -> staging -> dimension/fact.

Jalankan: python etl/run_elt.py
Setup tabel dilakukan terlebih dahulu melalui SQL 00-02, bukan oleh script ini.
"""

import os
from pathlib import Path
import sys

from dotenv import load_dotenv
from sqlalchemy import MetaData, Table, create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.exc import SQLAlchemyError


ROOT = Path(__file__).resolve().parents[1]

# Hanya memilih baris; kolom dan nilainya tetap seperti sumber.
# EXISTS mencegah satu item PO disalin dua kali saat diterima melalui dua GR.
EXTRACT_QUERIES = {
    "suppliers": "SELECT * FROM oltp.suppliers",
    "products": "SELECT * FROM oltp.products",
    "warehouses": "SELECT * FROM oltp.warehouses",
    "customers": "SELECT * FROM oltp.customers",
    "purchase_orders": """
        SELECT po.* FROM oltp.purchase_orders po
        WHERE EXISTS (
            SELECT 1 FROM oltp.goods_receipts gr
            WHERE gr.purchase_order_id = po.purchase_order_id AND gr.posted_at IS NOT NULL
        )
    """,
    "purchase_order_items": """
        SELECT poi.* FROM oltp.purchase_order_items poi
        WHERE EXISTS (
            SELECT 1 FROM oltp.goods_receipt_items gri
            JOIN oltp.goods_receipts gr USING (goods_receipt_id)
            WHERE gri.purchase_order_item_id = poi.purchase_order_item_id
              AND gr.posted_at IS NOT NULL
        )
    """,
    "goods_receipts": "SELECT * FROM oltp.goods_receipts WHERE posted_at IS NOT NULL",
    "goods_receipt_items": """
        SELECT gri.* FROM oltp.goods_receipt_items gri
        JOIN oltp.goods_receipts gr USING (goods_receipt_id)
        WHERE gr.posted_at IS NOT NULL
    """,
    "sales_orders": """
        SELECT so.* FROM oltp.sales_orders so
        WHERE EXISTS (
            SELECT 1 FROM oltp.goods_issues gi
            WHERE gi.sales_order_id = so.sales_order_id AND gi.posted_at IS NOT NULL
        )
    """,
    "sales_order_items": """
        SELECT soi.* FROM oltp.sales_order_items soi
        WHERE EXISTS (
            SELECT 1 FROM oltp.goods_issue_items gii
            JOIN oltp.goods_issues gi USING (goods_issue_id)
            WHERE gii.sales_order_item_id = soi.sales_order_item_id
              AND gi.posted_at IS NOT NULL
        )
    """,
    "goods_issues": "SELECT * FROM oltp.goods_issues WHERE posted_at IS NOT NULL",
    "goods_issue_items": """
        SELECT gii.* FROM oltp.goods_issue_items gii
        JOIN oltp.goods_issues gi USING (goods_issue_id)
        WHERE gi.posted_at IS NOT NULL
    """,
    "inventory_movements": """
        SELECT im.* FROM oltp.inventory_movements im
        WHERE EXISTS (
            SELECT 1 FROM oltp.goods_receipt_items gri
            JOIN oltp.goods_receipts gr USING (goods_receipt_id)
            WHERE gri.goods_receipt_item_id = im.goods_receipt_item_id
              AND gr.posted_at IS NOT NULL
        ) OR EXISTS (
            SELECT 1 FROM oltp.goods_issue_items gii
            JOIN oltp.goods_issues gi USING (goods_issue_id)
            WHERE gii.goods_issue_item_id = im.goods_issue_item_id
              AND gi.posted_at IS NOT NULL
        )
    """,
}


def database_url(database):
    """URL.create menerima password apa adanya, termasuk karakter @ atau #."""
    return URL.create(
        "postgresql+psycopg2",
        username=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        database=database,
    )


def run_validation(connection, filename):
    """SQL mengembalikan nama pemeriksaan dan jumlah baris yang bermasalah."""
    sql = (ROOT / "sql" / "dwh" / filename).read_text(encoding="utf-8")
    for check in connection.execute(text(sql)).mappings():
        if check["failures"] != 0:
            raise ValueError(f"{check['check_name']}: {check['failures']} baris bermasalah")
        print(f"  OK: {check['check_name']}")


def main():
    load_dotenv(ROOT / ".env")
    source_name = os.getenv("OLTP_DATABASE", "ndc_oltp")
    target_name = os.getenv("DWH_DATABASE", "ndc_dwh")
    if source_name == target_name:
        raise ValueError("Database sumber dan tujuan harus berbeda")

    source_engine = create_engine(
        database_url(source_name), isolation_level="REPEATABLE READ", hide_parameters=True
    )
    target_engine = create_engine(database_url(target_name), hide_parameters=True)
    try:
        # 1. EXTRACT: seluruh SELECT melihat snapshot sumber yang sama.
        print(f"1. Extract dari {source_name}")
        extracted = {}
        with source_engine.connect() as source, source.begin():
            source.execute(text("SET TRANSACTION READ ONLY"))
            for name, query in EXTRACT_QUERIES.items():
                extracted[name] = [dict(row) for row in source.execute(text(query)).mappings()]
                print(f"  {name}: {len(extracted[name])} baris")

        # Satu transaksi tujuan: exception apa pun menyebabkan ROLLBACK otomatis.
        with target_engine.begin() as target:
            # Cegah dua eksekusi script ini melakukan refresh bersamaan.
            if not target.scalar(text("SELECT pg_try_advisory_xact_lock(20261116)")):
                raise ValueError("Pipeline lain masih berjalan; coba lagi setelah selesai")

            # 2. LOAD: refresh hanya tabel staging yang tercantum dalam script.
            print(f"2. Load ke {target_name}.staging")
            names = ", ".join(f"staging.{name}" for name in EXTRACT_QUERIES)
            target.execute(text(f"TRUNCATE TABLE {names}"))
            metadata = MetaData(schema="staging")
            for name, rows in extracted.items():
                table = Table(name, metadata, autoload_with=target)
                for start in range(0, len(rows), 1000):
                    target.execute(table.insert(), rows[start:start + 1000])
                loaded = target.scalar(text(f"SELECT COUNT(*) FROM staging.{name}"))
                if loaded != len(rows):
                    raise ValueError(f"Jumlah baris staging.{name} tidak sesuai extract")

            print("3. Validasi staging")
            run_validation(target, "03_validate_staging.sql")

            # 3. TRANSFORM: seluruh logika bisnis ada di SQL, bukan Python.
            print("4. Transform staging ke dwh")
            transform = (ROOT / "sql/dwh/04_transform.sql").read_text(encoding="utf-8")
            target.exec_driver_sql(transform)

            print("5. Validasi DWH")
            run_validation(target, "05_validate_dwh.sql")
            for name in ("fact_receiving", "fact_sales", "fact_inventory"):
                count = target.scalar(text(f"SELECT COUNT(*) FROM dwh.{name}"))
                print(f"  {name}: {count} baris")

        print("Selesai. COMMIT berhasil; staging dan DWH sudah diperbarui.")
    finally:
        source_engine.dispose()
        target_engine.dispose()


if __name__ == "__main__":
    try:
        main()
    except (SQLAlchemyError, ValueError, OSError) as error:
        print(f"ELT gagal: {error}", file=sys.stderr)
        print("Perubahan pada transaksi tujuan dibatalkan; perbaiki masalah lalu ulangi.", file=sys.stderr)
        sys.exit(1)
