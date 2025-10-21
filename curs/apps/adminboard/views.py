from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView
from django.http import HttpResponseForbidden
from django.db import connection


class AdminDashboardView(LoginRequiredMixin, TemplateView):
    template_name = "adminboard/index.html"

    def dispatch(self, request, *args, **kwargs):
        if getattr(request.user, "role", None) != "ADMIN":
            return HttpResponseForbidden("Только для администраторов")
        return super().dispatch(request, *args, **kwargs)

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        q = (self.request.GET.get("q") or "").strip()
        with connection.cursor() as cur:
            # Проекты (фильтр по имени/специализации)
            cur.execute(
                """
                SELECT project_id, project_name, project_status, release_date, specialization
                FROM projects
                WHERE (%s = '' OR project_name ILIKE '%%'||%s||'%%' OR specialization ILIKE '%%'||%s||'%%')
                ORDER BY project_id DESC
                LIMIT 200
                """,
                [q, q, q],
            )
            cols = [c[0] for c in cur.description]
            ctx["projects"] = [dict(zip(cols, row)) for row in cur.fetchall()]

            # Пользователи
            cur.execute(
                """
                SELECT user_id, login, role, created_at
                FROM users
                WHERE (%s = '' OR login ILIKE '%%'||%s||'%%')
                ORDER BY user_id DESC
                LIMIT 200
                """,
                [q, q],
            )
            cols = [c[0] for c in cur.description]
            ctx["users"] = [dict(zip(cols, row)) for row in cur.fetchall()]

            # Задачи: агрегаты (для сводки)
            cur.execute("SELECT count(*) FROM tasks")
            ctx["tasks_total"] = cur.fetchone()[0]
            cur.execute("SELECT count(*) FROM reports")
            ctx["reports_total"] = cur.fetchone()[0]

            # Логи админов (как есть сейчас). Расширим позже.
            cur.execute(
                """
                SELECT admin_log_id, admin_id, admin_action, log_created_at
                FROM admin_logs ORDER BY log_created_at DESC LIMIT 200
                """
            )
            cols = [c[0] for c in cur.description]
            ctx["logs"] = [dict(zip(cols, row)) for row in cur.fetchall()]

        ctx["q"] = q
        return ctx
