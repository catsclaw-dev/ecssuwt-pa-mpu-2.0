# apps/accounts/migrations/0001_initial.py
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = []

    operations = [
        migrations.SeparateDatabaseAndState(
            # В БД НЕ ДЕЛАЕМ НИЧЕГО
            database_operations=[],
            # В состоянии миграций объявим только первичный ключ — этого
            # достаточно, чтобы внешние миграции могли сослаться на модель.
            state_operations=[
                migrations.CreateModel(
                    name="User",
                    fields=[
                        (
                            "user_id",
                            models.BigAutoField(primary_key=True, serialize=False),
                        ),
                    ],
                    options={
                        "db_table": "users",
                        "managed": False,  # напоминание: таблицу создали SQL-скриптами
                    },
                ),
            ],
        ),
    ]
