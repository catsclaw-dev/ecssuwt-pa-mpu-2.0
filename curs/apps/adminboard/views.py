from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView
from django.http import HttpResponseForbidden, Http404
from django.shortcuts import render, redirect
from django.views.decorators.http import require_http_methods, require_POST
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.db import connection
from django.contrib.auth.hashers import make_password


# ---------- helpers ----------
def _is_admin(request):
    return (
        request.user.is_authenticated and getattr(request.user, "role", None) == "ADMIN"
    )


def _admin_or_403(request):
    if not _is_admin(request):
        return HttpResponseForbidden("Только для администраторов")


def _fetchall_dict(cur):
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def _fetchone_dict(cur):
    cols = [c[0] for c in cur.description]
    r = cur.fetchone()
    return dict(zip(cols, r)) if r else None


# ---------- dashboard ----------
class AdminDashboardView(LoginRequiredMixin, TemplateView):
    template_name = "adminboard/index.html"

    def dispatch(self, request, *args, **kwargs):
        if not _is_admin(request):
            return HttpResponseForbidden("Только для администраторов")
        return super().dispatch(request, *args, **kwargs)


# ---------- USERS ----------
PAGE_SIZE = 100
ROLES = ("ADMIN", "PROFESSOR", "STUDENT")


@login_required
def users_list(request):
    if resp := _admin_or_403(request):
        return resp

    q = (request.GET.get("q") or "").strip()
    role = (request.GET.get("role") or "").strip().upper()
    page = max(int(request.GET.get("page", 1) or 1), 1)
    offset = (page - 1) * PAGE_SIZE

    # если роль не выбрана — передаём NULL и проверяем IS NULL в SQL
    role_param = role if role in ROLES else None

    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT user_id, login, role, first_name, last_name, created_at
            FROM users
            WHERE (%s = '' OR login ILIKE '%%'||%s||'%%'
                           OR first_name ILIKE '%%'||%s||'%%'
                           OR last_name  ILIKE '%%'||%s||'%%')
              AND (%s IS NULL OR role = %s)
            ORDER BY user_id DESC
            LIMIT %s OFFSET %s
            """,
            [q, q, q, q, role_param, role_param, PAGE_SIZE, offset],
        )
        users = _fetchall_dict(cur)

    ctx = {
        "users": users,
        "q": q,
        "role": role if role in ROLES else "",
        "roles": ROLES,
        "page": page,
        "page_size": PAGE_SIZE,
        "has_next": len(users) == PAGE_SIZE,
    }
    return render(request, "adminboard/users_list.html", ctx)


@login_required
@require_http_methods(["GET", "POST"])
def user_new(request):
    if resp := _admin_or_403(request):
        return resp

    if request.method == "POST":
        login = (request.POST.get("login") or "").strip()
        role = (request.POST.get("role") or "").strip().upper()
        first = (request.POST.get("first_name") or "").strip()
        last = (request.POST.get("last_name") or "").strip()
        pwd = (request.POST.get("password") or "").strip()

        if not (login and role in ROLES and first and last and pwd):
            messages.error(request, "Заполните обязательные поля")
        else:
            ph = make_password(pwd)
            try:
                with connection.cursor() as cur:
                    cur.execute(
                        """INSERT INTO users (login, role, first_name, last_name, password_hash)
                           VALUES (%s,%s,%s,%s,%s)
                           RETURNING user_id""",
                        [login, role, first, last, ph],
                    )
                    uid = cur.fetchone()[0]
                    # синхронизируем роль-таблицы
                    if role == "STUDENT":
                        cur.execute(
                            "INSERT INTO students (user_id, group_number, faculty) VALUES (%s,'UNSET','UNSET') ON CONFLICT DO NOTHING",
                            [uid],
                        )
                    elif role == "PROFESSOR":
                        cur.execute(
                            "INSERT INTO professors (user_id, department, faculty) VALUES (%s,'UNSET','UNSET') ON CONFLICT DO NOTHING",
                            [uid],
                        )
                    elif role == "ADMIN":
                        cur.execute(
                            "INSERT INTO admins (user_id) VALUES (%s) ON CONFLICT DO NOTHING",
                            [uid],
                        )
                messages.success(request, "Пользователь создан")
                return redirect("adminboard:users-list")
            except Exception as e:
                # аккуратно ловим уникальность логина
                if getattr(e, "pgcode", "") == errors.UniqueViolation.sqlstate:
                    messages.error(request, "Такой логин уже существует")
                else:
                    messages.error(request, "Ошибка сохранения")
    return render(
        request,
        "adminboard/user_form.html",
        {"mode": "new", "roles": ROLES, "user": {}},
    )


@login_required
@require_http_methods(["GET", "POST"])
def user_edit(request, user_id: int):
    if resp := _admin_or_403(request):
        return resp

    with connection.cursor() as cur:
        cur.execute("SELECT * FROM users WHERE user_id=%s", [user_id])
        user = _fetchone_dict(cur)
    if not user:
        from django.http import Http404

        raise Http404("User not found")

    if request.method == "POST":
        login = (request.POST.get("login") or "").strip()
        role = (request.POST.get("role") or "").strip().upper()
        first = (request.POST.get("first_name") or "").strip()
        last = (request.POST.get("last_name") or "").strip()
        pwd = (request.POST.get("password") or "").strip() or None

        if not (login and role in ROLES and first and last):
            messages.error(request, "Заполните обязательные поля")
        else:
            with connection.cursor() as cur:
                if pwd:
                    ph = make_password(pwd)
                    cur.execute(
                        """UPDATE users
                           SET login=%s, role=%s, first_name=%s, last_name=%s, password_hash=%s
                           WHERE user_id=%s""",
                        [login, role, first, last, ph, user_id],
                    )
                else:
                    cur.execute(
                        """UPDATE users
                           SET login=%s, role=%s, first_name=%s, last_name=%s
                           WHERE user_id=%s""",
                        [login, role, first, last, user_id],
                    )
                # привести роль-таблицы в соответствие
                cur.execute("DELETE FROM admins     WHERE user_id=%s", [user_id])
                cur.execute("DELETE FROM professors WHERE user_id=%s", [user_id])
                cur.execute("DELETE FROM students   WHERE user_id=%s", [user_id])
                if role == "ADMIN":
                    cur.execute("INSERT INTO admins (user_id) VALUES (%s)", [user_id])
                elif role == "PROFESSOR":
                    cur.execute(
                        "INSERT INTO professors (user_id, department, faculty) VALUES (%s,'UNSET','UNSET')",
                        [user_id],
                    )
                elif role == "STUDENT":
                    cur.execute(
                        "INSERT INTO students (user_id, group_number, faculty) VALUES (%s,'UNSET','UNSET')",
                        [user_id],
                    )

            messages.success(request, "Пользователь обновлён")
            return redirect("adminboard:users-list")

    return render(
        request,
        "adminboard/user_form.html",
        {"mode": "edit", "user": user, "roles": ROLES},
    )


@login_required
@require_POST
def user_delete(request, user_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute("DELETE FROM users WHERE user_id=%s", [user_id])
    messages.info(request, "Пользователь удалён")
    return redirect("adminboard:users-list")


# ---------- PROJECTS ----------
@login_required
def projects_list(request):
    if resp := _admin_or_403(request):
        return resp
    q = (request.GET.get("q") or "").strip()
    status = request.GET.get("status") or None  # ← None вместо ''
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT project_id, project_name, project_status, release_date, specialization
            FROM projects
            WHERE (%s = '' OR project_name ILIKE '%%'||%s||'%%' OR specialization ILIKE '%%'||%s||'%%')
                AND (%s IS NULL OR project_status = %s::project_status)
            ORDER BY project_id DESC
            LIMIT 300
            """,
            [q, q, q, status, status],
        )
        items = _fetchall_dict(cur)
    statuses = ("active", "paused", "archived")
    return render(
        request,
        "adminboard/projects_list.html",
        {"items": items, "q": q, "status": status, "statuses": statuses},
    )


@login_required
@require_http_methods(["GET", "POST"])
def project_new(request):
    if resp := _admin_or_403(request):
        return resp
    if request.method == "POST":
        name = (request.POST.get("project_name") or "").strip()
        spec = (request.POST.get("specialization") or "").strip() or None
        desc = (request.POST.get("project_description") or "").strip() or None
        rel = request.POST.get("release_date") or None
        status = (request.POST.get("project_status") or "active").strip()
        if not name:
            messages.error(request, "Название обязательно")
        else:
            with connection.cursor() as cur:
                cur.execute(
                    """INSERT INTO projects (project_name, project_description, project_status, release_date, specialization)
                       VALUES (%s,%s,%s,%s,%s) RETURNING project_id""",
                    [name, desc, status, rel, spec],
                )
                pid = cur.fetchone()[0]
            messages.success(request, "Проект создан")
            return redirect("projects:project-detail", project_id=pid)
    return render(request, "adminboard/project_form.html", {"mode": "new"})


@login_required
@require_http_methods(["GET", "POST"])
def project_edit(request, project_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute("SELECT * FROM projects WHERE project_id=%s", [project_id])
        project = _fetchone_dict(cur)
    if not project:
        raise Http404("Проект не найден")

    if request.method == "POST":
        name = (request.POST.get("project_name") or "").strip()
        spec = (request.POST.get("specialization") or "").strip() or None
        desc = (request.POST.get("project_description") or "").strip() or None
        rel = request.POST.get("release_date") or None
        status = (request.POST.get("project_status") or "active").strip()
        with connection.cursor() as cur:
            cur.execute(
                """UPDATE projects
                   SET project_name=%s, project_description=%s, project_status=%s, release_date=%s, specialization=%s
                   WHERE project_id=%s""",
                [name, desc, status, rel, spec, project_id],
            )
        messages.success(request, "Проект обновлён")
        return redirect("adminboard:projects-list")

    return render(
        request, "adminboard/project_form.html", {"mode": "edit", "project": project}
    )


@login_required
@require_POST
def project_delete(request, project_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute("DELETE FROM projects WHERE project_id=%s", [project_id])
    messages.info(request, "Проект удалён")
    return redirect("adminboard:projects-list")


# ---------- TASKS ----------
@login_required
def tasks_list(request):
    if resp := _admin_or_403(request):
        return resp
    q = (request.GET.get("q") or "").strip()
    status = (request.GET.get("status") or "").strip()
    proj = request.GET.get("project_id")
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT t.task_id, t.task_name, t.task_status, t.task_deadline,
                   p.project_id, p.project_name
            FROM tasks t JOIN projects p ON p.project_id=t.project_id
            WHERE (%s='' OR t.task_name ILIKE '%%'||%s||'%%')
              AND (%s='' OR t.task_status=%s)
              AND (%s IS NULL OR p.project_id = %s::bigint)
            ORDER BY t.task_id DESC
            LIMIT 300
            """,
            [q, q, status, status, proj, proj],
        )
        items = _fetchall_dict(cur)
        cur.execute(
            "SELECT project_id, project_name FROM projects ORDER BY project_id DESC LIMIT 500"
        )
        projs = _fetchall_dict(cur)
    return render(
        request,
        "adminboard/tasks_list.html",
        {"items": items, "q": q, "status": status, "projs": projs, "project_id": proj},
    )


@login_required
@require_http_methods(["GET", "POST"])
def task_new_admin(request):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute(
            "SELECT project_id, project_name FROM projects ORDER BY project_id DESC LIMIT 500"
        )
        projs = _fetchall_dict(cur)

    if request.method == "POST":
        pid = request.POST.get("project_id")
        name = (request.POST.get("task_name") or "").strip()
        desc = (request.POST.get("task_description") or "").strip() or None
        status = (request.POST.get("task_status") or "open").strip()
        deadline = request.POST.get("task_deadline") or None
        exec_sid = request.POST.get("executor_student") or None
        if not (pid and name):
            messages.error(request, "Выберите проект и введите название")
        else:
            with connection.cursor() as cur:
                cur.execute(
                    """INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
                       VALUES (%s,%s,%s,%s,%s,%s)""",
                    [pid, name, desc, exec_sid, status, deadline],
                )
            messages.success(request, "Задача создана")
            return redirect("adminboard:tasks-list")

    # список студентов под выбранный проект
    students = []
    sel_pid = request.GET.get("project_id")
    if sel_pid:
        with connection.cursor() as cur:
            cur.execute(
                """
                SELECT s.student_id, u.last_name||' '||u.first_name
                FROM project_members m
                JOIN students s ON s.student_id=m.member_student
                JOIN users u ON u.user_id=s.user_id
                WHERE m.project_id=%s AND m.member_student IS NOT NULL
                ORDER BY 2
                """,
                [sel_pid],
            )
            students = cur.fetchall()
    return render(
        request,
        "adminboard/task_form.html",
        {"mode": "new", "projs": projs, "students": students, "sel_pid": sel_pid},
    )


@login_required
@require_http_methods(["GET", "POST"])
def task_edit_admin(request, task_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute(
            """SELECT t.*, p.project_name FROM tasks t JOIN projects p ON p.project_id=t.project_id WHERE t.task_id=%s""",
            [task_id],
        )
        task = _fetchone_dict(cur)
    if not task:
        raise Http404("Задача не найдена")

    # студенты проекта
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT s.student_id, u.last_name||' '||u.first_name
            FROM project_members m
            JOIN students s ON s.student_id=m.member_student
            JOIN users u ON u.user_id=s.user_id
            WHERE m.project_id=%s AND m.member_student IS NOT NULL
            ORDER BY 2
            """,
            [task["project_id"]],
        )
        students = cur.fetchall()

    if request.method == "POST":
        name = (request.POST.get("task_name") or "").strip()
        desc = (request.POST.get("task_description") or "").strip() or None
        status = (request.POST.get("task_status") or "open").strip()
        deadline = request.POST.get("task_deadline") or None
        exec_sid = request.POST.get("executor_student") or None
        with connection.cursor() as cur:
            cur.execute(
                """UPDATE tasks
                   SET task_name=%s, task_description=%s, task_status=%s, task_deadline=%s, executor_student=%s
                   WHERE task_id=%s""",
                [name, desc, status, deadline, exec_sid, task_id],
            )
        messages.success(request, "Задача обновлена")
        return redirect("adminboard:tasks-list")

    return render(
        request,
        "adminboard/task_form.html",
        {"mode": "edit", "task": task, "students": students},
    )


@login_required
@require_POST
def task_delete_admin(request, task_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute("DELETE FROM tasks WHERE task_id=%s", [task_id])
    messages.info(request, "Задача удалена")
    return redirect("adminboard:tasks-list")
