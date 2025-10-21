from django.http import HttpResponseForbidden, HttpResponseBadRequest
from django.db import connection


class ProjectAccessMixin:
    def _is_member(self, user, project_id: int) -> bool:
        role = getattr(user, "role", None)
        uid = getattr(user, "user_id", None) or user.pk
        if role == "ADMIN":
            return True
        with connection.cursor() as cur:
            if role == "STUDENT":
                cur.execute(
                    """
                    SELECT 1 FROM project_members pm
                    JOIN students s ON s.student_id = pm.member_student
                    WHERE pm.project_id=%s AND s.user_id=%s
                    LIMIT 1
                """,
                    [project_id, uid],
                )
            elif role == "PROFESSOR":
                cur.execute(
                    """
                    SELECT 1 FROM project_members pm
                    JOIN professors p ON p.professor_id = pm.member_prof
                    WHERE pm.project_id=%s AND p.user_id=%s
                    LIMIT 1
                """,
                    [project_id, uid],
                )
            else:
                return False
            return cur.fetchone() is not None

    def dispatch(self, request, *args, **kwargs):
        project_id = kwargs.get("project_id")
        if project_id is None:
            return HttpResponseBadRequest("project_id is required")
        if not self._is_member(request.user, project_id):
            return HttpResponseForbidden(
                "Доступ только участникам проекта или администратору"
            )
        return super().dispatch(request, *args, **kwargs)
