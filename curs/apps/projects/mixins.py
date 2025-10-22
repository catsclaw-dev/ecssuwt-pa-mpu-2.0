from django.http import HttpResponseForbidden, HttpResponseBadRequest
from django.core.exceptions import PermissionDenied
from django.db import connection


def _is_active_member(user, project_id: int) -> bool:
    role = getattr(user, "role", "")
    uid = getattr(user, "user_id", None) or getattr(user, "pk", None)
    if not uid:
        return False
    with connection.cursor() as cur:
        if role == "STUDENT":
            cur.execute(
                """
                SELECT 1 FROM project_members m
                JOIN students s ON s.student_id = m.member_student
                WHERE m.project_id=%s AND s.user_id=%s AND m.left_at IS NULL
            """,
                [project_id, uid],
            )
        elif role == "PROFESSOR":
            cur.execute(
                """
                SELECT 1 FROM project_members m
                JOIN professors p ON p.professor_id = m.member_prof
                WHERE m.project_id=%s AND p.user_id=%s AND m.left_at IS NULL
            """,
                [project_id, uid],
            )
        else:
            return False
        return cur.fetchone() is not None


class ProjectAccessMixin:
    """Пускает ADMIN всегда, студентов/преподавателей — только если они участники проекта.
    (Это миксин именно для детальной страницы проекта.)"""

    def dispatch(self, request, *args, **kwargs):
        project_id = kwargs.get("project_id")
        role = getattr(request.user, "role", "")
        if role == "ADMIN":
            return super().dispatch(request, *args, **kwargs)
        if project_id and _is_active_member(request.user, project_id):
            return super().dispatch(request, *args, **kwargs)
        # КЛЮЧЕВОЕ: поднимаем PermissionDenied -> пойдёт в handler403 и 403.html
        raise PermissionDenied(
            "Доступ к странице проекта ограничен участниками и администратором."
        )
