from contextlib import suppress
from django.db import connection

ROLE_MAP = {
    "STUDENT": "role_student",
    "PROFESSOR": "role_professor",
    "ADMIN": "role_admin",
}
SKIP_PREFIXES = ("/login", "/logout", "/admin")  # не включаем SET ROLE на этих URL


def set_db_role(get_response):
    def middleware(request):
        # пропускаем спец-маршруты
        if any(request.path.startswith(p) for p in SKIP_PREFIXES):
            return get_response(request)

        user = getattr(request, "user", None)
        role = getattr(user, "role", None)
        role_name = ROLE_MAP.get(role) if isinstance(role, str) else None
        try:
            if role_name:
                with suppress(Exception):
                    with connection.cursor() as cur:
                        cur.execute(f"SET ROLE {role_name}")
            return get_response(request)
        finally:
            if role_name:
                with suppress(Exception):
                    with connection.cursor() as cur:
                        cur.execute("RESET ROLE")

    return middleware
