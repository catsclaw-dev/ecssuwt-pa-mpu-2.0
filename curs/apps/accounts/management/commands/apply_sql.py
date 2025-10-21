from django.core.management.base import BaseCommand
from django.db import connection, transaction
from pathlib import Path
from django.conf import settings

SQL_ORDER = [
    "00_extensions.sql",
    "01_types.sql",
    "02_schema.sql",
    "03_indexes.sql",
    "04_functions.sql",
    "05_triggers.sql",
    # "06_security.sql",
    "07_ins_user.sql",
    "08_project_schedule.sql",
    "09_admin_logs.sql",
    "10_try_stable_2.sql",
    "11_new_dls.sql",
    "12_create_dls.sql",
    "13_admin_dls.sql",
]


class Command(BaseCommand):
    help = "Apply SQL files from /db in order, tracking applied scripts."

    def handle(self, *args, **kwargs):
        base = Path(settings.BASE_DIR) / "db"
        with connection.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS schema_migrations (
                  filename text primary key,
                  applied_at timestamptz not null default now()
                )
            """)
        for fname in SQL_ORDER:
            path = base / fname
            if not path.exists():
                self.stdout.write(self.style.WARNING(f"Skip missing {fname}"))
                continue
            with connection.cursor() as cur:
                cur.execute(
                    "SELECT 1 FROM schema_migrations WHERE filename = %s", [fname]
                )
                if cur.fetchone():
                    self.stdout.write(self.style.NOTICE(f"Already applied: {fname}"))
                    continue
            sql = path.read_text(encoding="utf-8")
            self.stdout.write(f"Applying {fname} ...")
            with transaction.atomic():
                with connection.cursor() as cur:
                    cur.execute(sql)
                    cur.execute(
                        "INSERT INTO schema_migrations(filename) VALUES (%s)", [fname]
                    )
            self.stdout.write(self.style.SUCCESS(f"OK: {fname}"))
        self.stdout.write(self.style.SUCCESS("All done."))
