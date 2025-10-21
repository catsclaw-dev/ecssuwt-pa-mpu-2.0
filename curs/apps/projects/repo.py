from django.db import connection


def fetchall_dict(cur):
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def get_projects_for_student(student_id: int):
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT p.*
            FROM projects p
            JOIN project_members m ON m.project_id = p.project_id
            WHERE m.member_student = %s
            ORDER BY p.created_at DESC
        """,
            [student_id],
        )
        return fetchall_dict(cur)


def fetchone_dict(cur):
    cols = [c[0] for c in cur.description]
    row = cur.fetchone()
    return dict(zip(cols, row)) if row else None


def get_student_id_by_user(user_id: int) -> int | None:
    with connection.cursor() as cur:
        cur.execute("SELECT student_id FROM students WHERE user_id=%s", [user_id])
        r = cur.fetchone()
        return r[0] if r else None


def get_professor_id_by_user(user_id: int) -> int | None:
    with connection.cursor() as cur:
        cur.execute("SELECT professor_id FROM professors WHERE user_id=%s", [user_id])
        r = cur.fetchone()
        return r[0] if r else None


def get_projects_for_professor(professor_id: int):
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT p.*
            FROM projects p
            JOIN project_members m ON m.project_id = p.project_id
            WHERE m.member_prof = %s
            ORDER BY p.created_at DESC
            """,
            [professor_id],
        )
        return fetchall_dict(cur)


def get_projects_for_admin(limit: int = 200):
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT p.*
            FROM projects p
            ORDER BY p.created_at DESC
            LIMIT %s
            """,
            [limit],
        )
        return fetchall_dict(cur)


def get_project(project_id: int):
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
        return fetchone_dict(cur)


def get_project_members(project_id: int):
    sql = """
      SELECT 'STUDENT' AS kind, s.student_id AS id,
             u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
             m.role_in_team, m.joined_at, m.left_at
      FROM project_members m
      JOIN students s ON s.student_id = m.member_student
      JOIN users u    ON u.user_id    = s.user_id
      WHERE m.project_id=%s AND m.member_student IS NOT NULL
      UNION ALL
      SELECT 'PROFESSOR' AS kind, pr.professor_id AS id,
             u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
             m.role_in_team, m.joined_at, m.left_at
      FROM project_members m
      JOIN professors pr ON pr.professor_id = m.member_prof
      JOIN users u       ON u.user_id       = pr.user_id
      WHERE m.project_id=%s AND m.member_prof IS NOT NULL
      ORDER BY joined_at, fio
    """
    with connection.cursor() as cur:
        cur.execute(sql, [project_id, project_id])
        return fetchall_dict(cur)


def get_project_progress(project_id: int):
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT COALESCE(COUNT(*),0) AS total,
                   COALESCE(COUNT(*) FILTER (WHERE task_status='done'),0) AS done
            FROM tasks
            WHERE project_id=%s
            """,
            [project_id],
        )
        total, done = cur.fetchone()
        ratio = (done / total) if total else 0.0
        return {"total": total, "done": done, "ratio": ratio}


def get_project_tasks_with_status(project_id: int):
    sql = """
      SELECT t.task_id,
             t.task_name,
             t.task_description,
             t.task_deadline,
             t.task_status,
             lr.status AS last_report_status,
             CASE
               WHEN lr.status = 'approved'  THEN 'done'
               WHEN lr.status = 'needs_fix' THEN 'needs_fix'
               WHEN lr.status = 'submitted' THEN 'in_review'
               ELSE t.task_status::text
             END AS ui_status
      FROM tasks t
      LEFT JOIN LATERAL (
        SELECT r.status
        FROM reports r
        WHERE r.task_id = t.task_id
        ORDER BY r.submitted_at DESC
        LIMIT 1
      ) lr ON TRUE
      WHERE t.project_id = %s
      ORDER BY t.task_deadline NULLS LAST, t.task_id
    """
    with connection.cursor() as cur:
        cur.execute(sql, [project_id])
        return fetchall_dict(cur)


def get_task_reports(task_id: int, limit: int = 20):
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT r.report_id, r.status, r.submitted_at, r.reviewed_at,
                   r.file_path, r.external_url,
                   u.login AS student_login
            FROM reports r
            JOIN students s ON s.student_id = r.student_id
            JOIN users u    ON u.user_id    = s.user_id
            WHERE r.task_id = %s
            ORDER BY r.submitted_at DESC
            LIMIT %s
            """,
            [task_id, limit],
        )
        return fetchall_dict(cur)


def get_project_schedule(project_id: int):
    """
    Плейсхолдер: если таблицы project_schedule нет — вернёт [].
    В STEP 2.5 ниже есть DDL, если решим добавить расписание.
    """
    try:
        with connection.cursor() as cur:
            cur.execute(
                """
                SELECT schedule_id, title, starts_at, ends_at, location, description
                FROM project_schedule
                WHERE project_id=%s
                ORDER BY starts_at
                """,
                [project_id],
            )
            return fetchall_dict(cur)
    except Exception:
        return []
