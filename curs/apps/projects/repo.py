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
