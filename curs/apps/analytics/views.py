from django.views.generic import TemplateView
from django.db import connection


class AnalyticsHome(TemplateView):
    template_name = "analytics/home.html"


PAGE_SIZE = 100


class ProjectsRankingView(TemplateView):
    template_name = "analytics/projects_ranking.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        page = max(int(self.request.GET.get("page", 1)), 1)
        offset = (page - 1) * PAGE_SIZE

        with connection.cursor() as cur:
            cur.execute(
                """
                WITH t AS (
                  SELECT t.project_id,
                         COUNT(*) AS total,
                         COUNT(*) FILTER (WHERE t.task_status='done') AS done
                  FROM tasks t
                  GROUP BY t.project_id
                ),
                ra AS (
                  SELECT t.project_id,
                         MAX(COALESCE(r.reviewed_at, r.submitted_at)) AS last_activity
                  FROM tasks t
                  LEFT JOIN reports r ON r.task_id = t.task_id
                  GROUP BY t.project_id
                )
                SELECT p.project_id,
                       p.project_name,
                       p.project_status,
                       p.release_date,
                       p.specialization,
                       COALESCE(t.total, 0) AS total,
                       COALESCE(t.done, 0)  AS done,
                       CASE
                         WHEN COALESCE(t.total,0) = 0 THEN 0
                         ELSE ROUND(100.0 * COALESCE(t.done,0) / t.total, 2)
                       END AS ratio_pct,                -- 0..100
                       ra.last_activity
                FROM projects p
                LEFT JOIN t  ON t.project_id  = p.project_id
                LEFT JOIN ra ON ra.project_id = p.project_id
                ORDER BY ratio_pct DESC,
                         COALESCE(t.total,0) DESC,
                         ra.last_activity DESC NULLS LAST,
                         p.project_id DESC
                LIMIT %s OFFSET %s
                """,
                [PAGE_SIZE, offset],
            )
            cols = [c[0] for c in cur.description]
            ctx["items"] = [dict(zip(cols, r)) for r in cur.fetchall()]

        ctx["page"] = page
        ctx["page_size"] = PAGE_SIZE
        return ctx
