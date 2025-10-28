from django.views.generic import TemplateView
from django.db import connection


PAGE_SIZE = 24
PROJECT_STATUSES = ("active", "paused", "archived")


class ShowcaseListView(TemplateView):
    template_name = "showcase/list.html"

    def _fetchall_dict(self, cur):
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)

        # --- входные параметры
        q = (self.request.GET.get("q") or "").strip()
        status = (self.request.GET.get("status") or "").strip()
        spec = (self.request.GET.get("spec") or "").strip()
        show = (
            (self.request.GET.get("show") or "active").strip().lower()
        )  # active|archived|all
        sort = (self.request.GET.get("sort") or "release_desc").strip()

        try:
            page = max(int(self.request.GET.get("page", 1) or 1), 1)
        except Exception:
            page = 1
        offset = (page - 1) * PAGE_SIZE

        # --- динамические части (строго по белым спискам!)
        arch_sql = {
            "active": "p.archived_at IS NULL",
            "archived": "p.archived_at IS NOT NULL",
            "all": "TRUE",
        }.get(show, "p.archived_at IS NULL")

        order_by = {
            "release_desc": "p.release_date DESC NULLS LAST",
            "release_asc": "p.release_date ASC  NULLS LAST",
            "name_asc": "p.project_name ASC",
            "name_desc": "p.project_name DESC",
            "created_desc": "p.created_at DESC",
            "created_asc": "p.created_at ASC",
            "id_desc": "p.project_id DESC",
            "id_asc": "p.project_id ASC",
        }.get(sort, "p.release_date DESC NULLS LAST")

        status_param = status if status in PROJECT_STATUSES else None

        # --- запрос
        with connection.cursor() as cur:
            cur.execute(
                f"""
                SELECT p.project_id,
                       p.project_name,
                       p.project_status,
                       p.release_date,
                       p.specialization,
                       p.archived_at
                  FROM projects p
                 WHERE ({arch_sql})
                   AND (%s = '' OR p.project_name ILIKE '%%'||%s||'%%'
                               OR p.specialization ILIKE '%%'||%s||'%%')
                   AND (%s = '' OR p.specialization ILIKE '%%'||%s||'%%')
                   AND (%s IS NULL OR p.project_status = %s::project_status)
                 ORDER BY {order_by}
                 LIMIT %s OFFSET %s
                """,
                [
                    q,
                    q,
                    q,  # поиск по имени/специализации
                    spec,
                    spec,  # фильтр по спецу (отдельное поле)
                    status_param,
                    status_param,
                    PAGE_SIZE,
                    offset,
                ],
            )
            ctx["items"] = self._fetchall_dict(cur)

        # --- контекст для шаблона
        ctx.update(
            {
                "page": page,
                "page_size": PAGE_SIZE,
                "q": q,
                "status": status if status in PROJECT_STATUSES else "",
                "spec": spec,
                "show": show,
                "sort": sort,
                "statuses": PROJECT_STATUSES,
            }
        )
        return ctx


class ShowcaseDetailView(TemplateView):
    template_name = "showcase/detail.html"

    def get_context_data(self, project_id: int, **kwargs):
        ctx = super().get_context_data(**kwargs)
        with connection.cursor() as cur:
            cur.execute(
                """
                SELECT p.project_id,
                p.project_name,
                p.project_description,
                p.project_status,
                p.created_at,
                p.release_date,
                p.specialization
                FROM projects p
                WHERE p.project_id = %s
                """,
                [project_id],
            )
            row = cur.fetchone()
            if not row:
                from django.http import Http404

                raise Http404("Проект не найден")
            cols = [c[0] for c in cur.description]
            ctx["project"] = dict(zip(cols, row))
        return ctx
