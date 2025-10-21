from django.views.generic import TemplateView
from django.db import connection


PAGE_SIZE = 100


class ShowcaseListView(TemplateView):
    template_name = "showcase/list.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        page = max(int(self.request.GET.get("page", 1)), 1)
        offset = (page - 1) * PAGE_SIZE
        with connection.cursor() as cur:
            cur.execute(
                """
                SELECT p.project_id,
                p.project_name,
                p.project_status,
                p.release_date,
                p.specialization
                FROM projects p
                ORDER BY p.project_id DESC
                LIMIT %s OFFSET %s
                """,
                [PAGE_SIZE, offset],
            )
            cols = [c[0] for c in cur.description]
            ctx["items"] = [dict(zip(cols, row)) for row in cur.fetchall()]
        ctx["page"] = page
        ctx["page_size"] = PAGE_SIZE
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
