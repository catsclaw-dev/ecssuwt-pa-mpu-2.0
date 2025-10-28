from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView
from django.http import HttpResponseForbidden, Http404, JsonResponse
from django.shortcuts import render, redirect
from django.views.decorators.http import require_http_methods, require_POST
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.db import connection
from django.contrib.auth.hashers import make_password
import json


# ---------- helpers ----------
def _is_admin(request):
    return (
        request.user.is_authenticated and getattr(request.user, "role", "") == "ADMIN"
    )


def _fetchall_dict(cur):
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def _admin_or_403(request):
    if not _is_admin(request):
        return HttpResponseForbidden("Только для администраторов")


def _fetchone_dict(cur):
    cols = [c[0] for c in cur.description]
    r = cur.fetchone()
    return dict(zip(cols, r)) if r else None


# ===== helpers for project membership management =====
def _prof_id_by_user(uid):
    with connection.cursor() as cur:
        cur.execute("SELECT professor_id FROM professors WHERE user_id=%s", [uid])
        r = cur.fetchone()
        return r[0] if r else None


def _is_prof_member_of_project(pid, project_id) -> bool:
    if not pid:
        return False
    with connection.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM project_members WHERE project_id=%s AND member_prof=%s",
            [project_id, pid],
        )
        return cur.fetchone() is not None


def _can_manage_project(request, project_id) -> bool:
    if not request.user.is_authenticated:
        return False
    if getattr(request.user, "role", None) == "ADMIN":
        return True
    if getattr(request.user, "role", None) == "PROFESSOR":
        pid = _prof_id_by_user(
            getattr(request.user, "user_id", None) or request.user.pk
        )
        return _is_prof_member_of_project(pid, project_id)
    return False


def _member_project(member_id) -> int | None:
    with connection.cursor() as cur:
        cur.execute("SELECT project_id FROM project_members WHERE id=%s", [member_id])
        r = cur.fetchone()
        return r[0] if r else None


# =====================================================


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
    show = (request.GET.get("show") or "active").strip().lower()  # active|archived|all
    page = max(int(request.GET.get("page", 1) or 1), 1)
    offset = (page - 1) * PAGE_SIZE

    role_param = role if role in ROLES else None
    arch_sql = {
        "active": "archived_at IS NULL",
        "archived": "archived_at IS NOT NULL",
        "all": "TRUE",
    }.get(show, "archived_at IS NULL")

    with connection.cursor() as cur:
        cur.execute(
            f"""
            SELECT user_id, login, role, first_name, last_name, created_at, archived_at,
                   (archived_at IS NOT NULL) AS is_archived
            FROM users
            WHERE (%s = '' OR login ILIKE '%%'||%s||'%%'
                           OR first_name ILIKE '%%'||%s||'%%'
                           OR last_name  ILIKE '%%'||%s||'%%')
              AND ({arch_sql})
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
        "show": show,
        "page": page,
        "page_size": PAGE_SIZE,
        "has_next": len(users) == PAGE_SIZE,
    }
    return render(request, "adminboard/users_list.html", ctx)


@login_required
@require_POST
def user_archive(request, user_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute(
            "UPDATE users SET archived_at = COALESCE(archived_at, now()) WHERE user_id=%s",
            [user_id],
        )
    messages.success(request, "Пользователь заархивирован")
    return redirect(request.META.get("HTTP_REFERER", "adminboard:users-list"))


@login_required
@require_POST
def user_unarchive(request, user_id: int):
    if resp := _admin_or_403(request):
        return resp
    with connection.cursor() as cur:
        cur.execute("UPDATE users SET archived_at = NULL WHERE user_id=%s", [user_id])
    messages.success(request, "Пользователь разархивирован")
    return redirect(request.META.get("HTTP_REFERER", "adminboard:users-list"))


@login_required
@require_http_methods(["GET", "POST"])
def user_new(request):
    if resp := _admin_or_403(request):
        return resp

    if request.method == "POST":
        login = (request.POST.get("login") or "").strip()
        role = (request.POST.get("role") or "").strip().upper()
        first = (request.POST.get("first_name") or "").strip()
        middle = (request.POST.get("middle_name") or "").strip()
        last = (request.POST.get("last_name") or "").strip()
        pwd = (request.POST.get("password") or "").strip()

        # контакты
        phone = (request.POST.get("contact_phone") or "").strip()
        email = (request.POST.get("contact_email") or "").strip()
        tg = (request.POST.get("contact_telegram") or "").strip()
        contacts = {"phone": phone, "email": email, "telegram": tg}

        # поля по роли
        st_group = (request.POST.get("st_group_number") or "").strip()
        st_faculty = (request.POST.get("st_faculty") or "").strip()
        pr_dept = (request.POST.get("pr_department") or "").strip()
        pr_faculty = (request.POST.get("pr_faculty") or "").strip()

        # ВАЛИДАЦИЯ (всё обязательно)
        role_ok = role in ROLES
        base_ok = all(
            [login, role_ok, first, last, middle, pwd, phone, email]
        )  # контакты тоже обязательны
        role_ok_extra = (
            (role == "STUDENT" and st_group and st_faculty)
            or (role == "PROFESSOR" and pr_dept and pr_faculty)
            or (role == "ADMIN")
        )

        if not (base_ok and role_ok_extra):
            messages.error(request, "Заполните все обязательные поля.")
        else:
            ph = make_password(pwd)
            try:
                with connection.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO users (login, role, first_name, middle_name, last_name, password_hash, user_contacts)
                        VALUES (%s,%s,%s,%s,%s,%s,%s::jsonb)
                        RETURNING user_id
                        """,
                        [
                            login,
                            role,
                            first,
                            middle,
                            last,
                            ph,
                            json.dumps(contacts, ensure_ascii=False),
                        ],
                    )
                    uid = cur.fetchone()[0]

                    if role == "STUDENT":
                        cur.execute(
                            "INSERT INTO students (user_id, group_number, faculty) VALUES (%s,%s,%s)",
                            [uid, st_group, st_faculty],
                        )
                    elif role == "PROFESSOR":
                        cur.execute(
                            "INSERT INTO professors (user_id, department, faculty) VALUES (%s,%s,%s)",
                            [uid, pr_dept, pr_faculty],
                        )
                    else:  # ADMIN
                        cur.execute("INSERT INTO admins (user_id) VALUES (%s)", [uid])

                messages.success(request, "Пользователь создан")
                return redirect("adminboard:users-list")
            except Exception:
                messages.error(request, "Ошибка сохранения (возможен дубликат логина)")

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

    # --- загрузим пользователя и связанные записи по ролям
    with connection.cursor() as cur:
        cur.execute("SELECT * FROM users WHERE user_id=%s", [user_id])
        user = _fetchone_dict(cur)
        if not user:
            raise Http404("User not found")

        cur.execute("SELECT * FROM students WHERE user_id=%s", [user_id])
        st = _fetchone_dict(cur)

        cur.execute("SELECT * FROM professors WHERE user_id=%s", [user_id])
        pr = _fetchone_dict(cur)

    if request.method == "POST":
        # --- чтение полей формы
        login = (request.POST.get("login") or "").strip()
        role = (request.POST.get("role") or "").strip().upper()
        first = (request.POST.get("first_name") or "").strip()
        middle = (request.POST.get("middle_name") or "").strip()
        last = (request.POST.get("last_name") or "").strip()
        pwd = (request.POST.get("password") or "").strip() or None

        phone = (request.POST.get("contact_phone") or "").strip()
        email = (request.POST.get("contact_email") or "").strip()
        tg = (request.POST.get("contact_telegram") or "").strip()
        contacts = {"phone": phone, "email": email, "telegram": tg}

        st_group = (request.POST.get("st_group_number") or "").strip()
        st_faculty = (request.POST.get("st_faculty") or "").strip()
        pr_dept = (request.POST.get("pr_department") or "").strip()
        pr_faculty = (request.POST.get("pr_faculty") or "").strip()

        # --- валидация как было
        role_ok = role in ROLES
        base_ok = all([login, role_ok, first, last, middle, phone, email])
        role_ok_extra = (
            (role == "STUDENT" and st_group and st_faculty)
            or (role == "PROFESSOR" and pr_dept and pr_faculty)
            or (role == "ADMIN")
        )
        if not (base_ok and role_ok_extra):
            messages.error(request, "Заполните все обязательные поля.")
        else:
            # --- дополнительная проверка ПЕРЕД изменением роли:
            # запрещаем убирать PROFESSOR, если есть проверенные отчёты
            old_role = user.get("role")
            if old_role == "PROFESSOR" and role != "PROFESSOR":
                with connection.cursor() as cur:
                    cur.execute(
                        "SELECT professor_id FROM professors WHERE user_id=%s",
                        [user_id],
                    )
                    r = cur.fetchone()
                    if r:
                        prof_id = r[0]
                        cur.execute(
                            """
                            SELECT COUNT(*)
                            FROM reports
                            WHERE reviewed_by_prof = %s
                              AND status IN ('approved','needs_fix')
                            """,
                            [prof_id],
                        )
                        cnt = cur.fetchone()[0]
                        if cnt > 0:
                            messages.error(
                                request,
                                f"Нельзя снять роль PROFESSOR: есть {cnt} проверенных отчётов с этим ревьюером.",
                            )
                            return redirect("adminboard:user-edit", user_id=user_id)

            # --- обновляем users
            with connection.cursor() as cur:
                if pwd:
                    ph = make_password(pwd)
                    cur.execute(
                        """UPDATE users SET
                               login=%s, role=%s,
                               first_name=%s, middle_name=%s, last_name=%s,
                               password_hash=%s, user_contacts=%s::jsonb
                           WHERE user_id=%s""",
                        [
                            login,
                            role,
                            first,
                            middle,
                            last,
                            ph,
                            json.dumps(contacts, ensure_ascii=False),
                            user_id,
                        ],
                    )
                else:
                    cur.execute(
                        """UPDATE users SET
                               login=%s, role=%s,
                               first_name=%s, middle_name=%s, last_name=%s,
                               user_contacts=%s::jsonb
                           WHERE user_id=%s""",
                        [
                            login,
                            role,
                            first,
                            middle,
                            last,
                            json.dumps(contacts, ensure_ascii=False),
                            user_id,
                        ],
                    )

                # --- синхронизация роль-таблиц БЕЗ потери professor_id
                if role == "PROFESSOR":
                    # upsert в professors
                    cur.execute(
                        "UPDATE professors SET department=%s, faculty=%s WHERE user_id=%s",
                        [pr_dept, pr_faculty, user_id],
                    )
                    if cur.rowcount == 0:
                        cur.execute(
                            "INSERT INTO professors (user_id, department, faculty) VALUES (%s,%s,%s)",
                            [user_id, pr_dept, pr_faculty],
                        )
                    # подчистим другие роли
                    cur.execute("DELETE FROM admins   WHERE user_id=%s", [user_id])
                    cur.execute("DELETE FROM students WHERE user_id=%s", [user_id])

                elif role == "STUDENT":
                    # upsert в students
                    cur.execute(
                        "UPDATE students SET group_number=%s, faculty=%s WHERE user_id=%s",
                        [st_group, st_faculty, user_id],
                    )
                    if cur.rowcount == 0:
                        cur.execute(
                            "INSERT INTO students (user_id, group_number, faculty) VALUES (%s,%s,%s)",
                            [user_id, st_group, st_faculty],
                        )
                    # подчистим другие роли
                    cur.execute("DELETE FROM admins WHERE user_id=%s", [user_id])
                    # professor теперь можно удалить (мы проверили, что нет reviewed-отчётов)
                    cur.execute("DELETE FROM professors WHERE user_id=%s", [user_id])

                else:  # role == "ADMIN"
                    # upsert в admins
                    cur.execute("SELECT 1 FROM admins WHERE user_id=%s", [user_id])
                    if not cur.fetchone():
                        cur.execute(
                            "INSERT INTO admins (user_id) VALUES (%s)", [user_id]
                        )
                    # подчистим другие роли
                    cur.execute("DELETE FROM students   WHERE user_id=%s", [user_id])
                    # professor теперь можно удалить (мы проверили выше при смене роли)
                    cur.execute("DELETE FROM professors WHERE user_id=%s", [user_id])

            messages.success(request, "Пользователь обновлён")
            return redirect("adminboard:users-list")

    # --- распакуем контакты для формы
    try:
        contacts = json.loads(user.get("user_contacts") or "{}")
    except Exception:
        contacts = {}
    user.setdefault("middle_name", "")
    user["contact_phone"] = contacts.get("phone", "")
    user["contact_email"] = contacts.get("email", "")
    user["contact_telegram"] = contacts.get("telegram", "")

    # --- подставим поля по роли
    user["st_group_number"] = (st or {}).get("group_number", "")
    user["st_faculty"] = (st or {}).get("faculty", "")
    user["pr_department"] = (pr or {}).get("department", "")
    user["pr_faculty"] = (pr or {}).get("faculty", "")

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
PROJECT_STATUSES = ("active", "paused", "archived")


@login_required
def user_lookup(request):
    if not _is_admin(request) and getattr(request.user, "role", None) != "PROFESSOR":
        return HttpResponseForbidden("Недостаточно прав")

    role = (request.GET.get("role") or "").strip().lower()  # student|professor
    q = (request.GET.get("q") or "").strip()
    limit = min(int(request.GET.get("limit", 20) or 20), 50)

    if role not in ("student", "professor"):
        return JsonResponse({"items": []})

    with connection.cursor() as cur:
        if role == "student":
            cur.execute(
                """
                SELECT s.student_id AS id,
                       u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                       s.group_number, s.faculty
                FROM students s JOIN users u ON u.user_id=s.user_id
                WHERE (%s='' OR u.last_name ILIKE '%%'||%s||'%%'
                              OR u.first_name ILIKE '%%'||%s||'%%'
                              OR s.group_number ILIKE '%%'||%s||'%%'
                              OR u.login ILIKE '%%'||%s||'%%')
                ORDER BY fio LIMIT %s
                """,
                [q, q, q, q, q, limit],
            )
            items = [
                {"id": r[0], "label": f"{r[1]} — гр. {r[2]} ({r[3]})"}
                for r in cur.fetchall()
            ]
        else:
            cur.execute(
                """
                SELECT p.professor_id AS id,
                       u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                       p.department, p.faculty
                FROM professors p JOIN users u ON u.user_id=p.user_id
                WHERE (%s='' OR u.last_name ILIKE '%%'||%s||'%%'
                              OR u.first_name ILIKE '%%'||%s||'%%'
                              OR p.department ILIKE '%%'||%s||'%%'
                              OR u.login ILIKE '%%'||%s||'%%')
                ORDER BY fio LIMIT %s
                """,
                [q, q, q, q, q, limit],
            )
            items = [
                {"id": r[0], "label": f"{r[1]} — {r[2]} ({r[3]})"}
                for r in cur.fetchall()
            ]
    return JsonResponse({"items": items})


@login_required
def projects_list(request):
    if resp := _admin_or_403(request):
        return resp
    q = (request.GET.get("q") or "").strip()
    status = (request.GET.get("status") or "").strip()
    show = (
        (request.GET.get("show") or "all").strip().lower()
    )  # active|archived|all — по archived_at
    status_param = status if status in PROJECT_STATUSES else None
    arch_sql = {
        "active": "p.archived_at IS NULL",
        "archived": "p.archived_at IS NOT NULL",
        "all": "TRUE",
    }.get(show, "TRUE")

    with connection.cursor() as cur:
        cur.execute(
            f"""
            SELECT p.project_id, p.project_name, p.project_status, p.release_date, p.specialization,
                   p.archived_at, (p.archived_at IS NOT NULL) AS is_archived
            FROM projects p
            WHERE (%s = '' OR p.project_name ILIKE '%%'||%s||'%%'
                           OR p.specialization ILIKE '%%'||%s||'%%')
              AND (%s IS NULL OR p.project_status = %s::project_status)
              AND ({arch_sql})
            ORDER BY p.project_id DESC
            LIMIT 300
            """,
            [q, q, q, status_param, status_param],
        )
        items = _fetchall_dict(cur)

    return render(
        request,
        "adminboard/projects_list.html",
        {
            "items": items,
            "q": q,
            "status": status_param or "",
            "statuses": PROJECT_STATUSES,
            "show": show,
        },
    )


@login_required
@require_http_methods(["GET", "POST"])
def project_new(request):
    if resp := _admin_or_403(request):
        return resp
    if request.method == "POST":
        name = (request.POST.get("project_name") or "").strip()
        spec = (request.POST.get("specialization") or "").strip()
        desc = (request.POST.get("project_description") or "").strip()
        rel = (request.POST.get("release_date") or "").strip()
        status = (request.POST.get("project_status") or "").strip()
        if not (name and spec and desc and rel and status in PROJECT_STATUSES):
            messages.error(request, "Заполните все поля корректно.")
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
    return render(
        request,
        "adminboard/project_form.html",
        {"mode": "new", "project": {}, "statuses": PROJECT_STATUSES},
    )


@login_required
@require_POST
def project_archive(request, project_id: int):
    if resp := _admin_or_403(request):
        return resp
    # В проектной модели архив — это и статус, и archived_at (ставится триггером/функцией)
    with connection.cursor() as cur:
        cur.execute(
            """
            UPDATE projects
               SET project_status='archived'
             WHERE project_id=%s AND project_status <> 'archived'
        """,
            [project_id],
        )
    messages.success(request, "Проект заархивирован")
    return redirect(request.META.get("HTTP_REFERER", "adminboard:projects-list"))


@login_required
@require_POST
def project_unarchive(request, project_id: int):
    if resp := _admin_or_403(request):
        return resp
    to_status = (request.POST.get("to_status") or "active").strip()
    if to_status not in ("active", "paused"):
        to_status = "active"
    with connection.cursor() as cur:
        # снятие archived_at делается прямо, статус возвращаем в выбранный
        cur.execute(
            """
            UPDATE projects
               SET archived_at = NULL,
                   project_status = %s::project_status
             WHERE project_id=%s
        """,
            [to_status, project_id],
        )
    messages.success(request, "Проект разархивирован")
    return redirect(request.META.get("HTTP_REFERER", "adminboard:projects-list"))


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
        spec = (request.POST.get("specialization") or "").strip()
        desc = (request.POST.get("project_description") or "").strip()
        rel = (request.POST.get("release_date") or "").strip()
        status = (request.POST.get("project_status") or "").strip()
        if not (name and spec and desc and rel and status in PROJECT_STATUSES):
            messages.error(request, "Заполните все поля корректно.")
        else:
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
        request,
        "adminboard/project_form.html",
        {"mode": "edit", "project": project, "statuses": PROJECT_STATUSES},
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
TASK_STATUSES = ("open", "in_review", "done")


@login_required
def tasks_list(request):
    if resp := _admin_or_403(request):
        return resp

    q = (request.GET.get("q") or "").strip()
    status = (request.GET.get("status") or "").strip()
    show = (
        (request.GET.get("show") or "active").strip().lower()
    )  # active|archived|all по t.archived_at
    status_param = status if status in TASK_STATUSES else None
    proj = (request.GET.get("project_id") or "").strip()
    proj_param = proj if proj.isdigit() else None

    page = max(int(request.GET.get("page", 1) or 1), 1)
    offset = (page - 1) * PAGE_SIZE
    arch_sql = {
        "active": "t.archived_at IS NULL",
        "archived": "t.archived_at IS NOT NULL",
        "all": "TRUE",
    }.get(show, "t.archived_at IS NULL")

    with connection.cursor() as cur:
        cur.execute(
            f"""
            SELECT t.task_id, t.task_name, t.task_status, t.task_deadline,
                   t.archived_at, (t.archived_at IS NOT NULL) AS is_archived,
                   p.project_id, p.project_name
            FROM tasks t
            JOIN projects p ON p.project_id = t.project_id
            WHERE (%s = '' OR t.task_name ILIKE '%%'||%s||'%%')
              AND (%s IS NULL OR t.task_status = %s::task_status)
              AND (%s IS NULL OR p.project_id = %s::bigint)
              AND ({arch_sql})
            ORDER BY t.task_id DESC
            LIMIT %s OFFSET %s
            """,
            [
                q,
                q,
                status_param,
                status_param,
                proj_param,
                proj_param,
                PAGE_SIZE,
                offset,
            ],
        )
        items = _fetchall_dict(cur)

        cur.execute(
            "SELECT project_id, project_name FROM projects ORDER BY project_id DESC LIMIT 1000"
        )
        projs = _fetchall_dict(cur)

    ctx = {
        "items": items,
        "q": q,
        "status": status_param or "",
        "project_id": proj_param or "",
        "statuses": TASK_STATUSES,
        "projs": projs,
        "show": show,
        "page": page,
        "page_size": PAGE_SIZE,
        "has_next": len(items) == PAGE_SIZE,
    }
    return render(request, "adminboard/tasks_list.html", ctx)


@login_required
@require_http_methods(["GET", "POST"])
def task_new_admin(request):
    if resp := _admin_or_403(request):  # ваш уже существующий хелпер
        return resp

    # ----- POST: создать задачу -----
    if request.method == "POST":
        pid = (request.POST.get("project_id") or "").strip()
        name = (request.POST.get("task_name") or "").strip()
        desc = (request.POST.get("task_description") or "").strip() or None
        status = (request.POST.get("task_status") or "").strip()
        deadline = (request.POST.get("task_deadline") or "").strip() or None
        exec_sid = (request.POST.get("executor_student") or "").strip() or None

        if not (pid.isdigit() and name and status in TASK_STATUSES):
            messages.error(request, "Укажите проект, название и корректный статус.")
        else:
            with connection.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
                    VALUES (%s,%s,%s,%s,%s::task_status,%s)
                    """,
                    [pid, name, desc, exec_sid, status, deadline],
                )
            messages.success(request, "Задача создана")
            return redirect("adminboard:tasks-list")

    # ----- GET: форма с серверным поиском проекта и загрузкой студентов -----
    q = (request.GET.get("q") or "").strip()
    page = max(int(request.GET.get("page", 1) or 1), 1)
    offset = (page - 1) * PAGE_SIZE

    sel_pid = (
        request.GET.get("project_id") or request.POST.get("project_id") or ""
    ).strip()
    sel_pid_param = sel_pid if sel_pid.isdigit() else None

    with connection.cursor() as cur:
        # список проектов по фильтру q (id/название/спец)
        cur.execute(
            """
            SELECT project_id, project_name, specialization, project_status
            FROM projects
            WHERE (%s = '' OR project_name ILIKE '%%'||%s||'%%'
                           OR specialization ILIKE '%%'||%s||'%%'
                           OR project_id::text ILIKE '%%'||%s||'%%')
            ORDER BY project_id DESC
            LIMIT %s OFFSET %s
            """,
            [q, q, q, q, PAGE_SIZE, offset],
        )
        projs = _fetchall_dict(cur)

        students = []
        if sel_pid_param:
            cur.execute(
                """
                SELECT s.student_id, u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio
                FROM project_members m
                JOIN students s ON s.student_id = m.member_student
                JOIN users u    ON u.user_id    = s.user_id
                WHERE m.project_id=%s AND m.member_student IS NOT NULL
                ORDER BY fio
                """,
                [sel_pid_param],
            )
            students = cur.fetchall()  # [(id, fio)]

    ctx = {
        "mode": "new",
        "task": {},
        "statuses": TASK_STATUSES,
        "projs": projs,
        "q": q,
        "page": page,
        "has_next": len(projs) == PAGE_SIZE,
        "sel_pid": sel_pid_param or "",
        "students": students,
    }
    return render(request, "adminboard/task_form.html", ctx)


@login_required
@require_http_methods(["GET", "POST"])
def task_edit_admin(request, task_id: int):
    if resp := _admin_or_403(request):
        return resp

    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT t.*, p.project_name
            FROM tasks t JOIN projects p ON p.project_id = t.project_id
            WHERE t.task_id=%s
            """,
            [task_id],
        )
        task = _fetchone_dict(cur)
    if not task:
        raise Http404("Задача не найдена")

    # студенты текущего проекта
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT s.student_id, u.last_name || ' ' || u.first_name || COALESCE(' '||u.middle_name,'') AS fio
            FROM project_members m
            JOIN students s ON s.student_id = m.member_student
            JOIN users u    ON u.user_id    = s.user_id
            WHERE m.project_id = %s AND m.member_student IS NOT NULL
            ORDER BY fio
            """,
            [task["project_id"]],
        )
        students = cur.fetchall()

    if request.method == "POST":
        name = (request.POST.get("task_name") or "").strip()
        desc = (request.POST.get("task_description") or "").strip() or None
        status = (request.POST.get("task_status") or "").strip()
        deadline = (request.POST.get("task_deadline") or "").strip() or None
        exec_sid = (request.POST.get("executor_student") or "").strip() or None

        if not (name and status in TASK_STATUSES):
            messages.error(request, "Название и корректный статус — обязательны.")
        else:
            with connection.cursor() as cur:
                cur.execute(
                    """
                    UPDATE tasks SET
                      task_name=%s,
                      task_description=%s,
                      task_status=%s::task_status,
                      task_deadline=%s,
                      executor_student=%s
                    WHERE task_id=%s
                    """,
                    [name, desc, status, deadline, exec_sid, task_id],
                )
            messages.success(request, "Задача обновлена")
            return redirect("adminboard:tasks-list")

    return render(
        request,
        "adminboard/task_form.html",
        {"mode": "edit", "task": task, "students": students, "statuses": TASK_STATUSES},
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


@login_required
def project_lookup(request):
    if resp := _admin_or_403(request):
        return resp
    q = (request.GET.get("q") or "").strip()
    limit = min(int(request.GET.get("limit", 20) or 20), 50)

    with connection.cursor() as cur:
        if q:
            cur.execute(
                """
                SELECT project_id, project_name, specialization, project_status
                FROM projects
                WHERE project_name ILIKE '%%'||%s||'%%'
                   OR specialization ILIKE '%%'||%s||'%%'
                   OR project_id::text ILIKE '%%'||%s||'%%'
                ORDER BY project_id DESC
                LIMIT %s
                """,
                [q, q, q, limit],
            )
        else:
            cur.execute(
                """
                SELECT project_id, project_name, specialization, project_status
                FROM projects
                ORDER BY project_id DESC
                LIMIT %s
                """,
                [limit],
            )
        items = _fetchall_dict(cur)

    return JsonResponse({"items": items})


@login_required
def project_members_admin(request, project_id: int):
    if not _is_admin(request):
        return HttpResponseForbidden("Только для администраторов")

    # фильтры
    sr = (request.GET.get("sr") or "student").lower()  # кого искать в "Кандидатах"
    c_q = (request.GET.get("c_q") or "").strip()  # поиск по кандидатам
    s_q = (request.GET.get("s_q") or "").strip()  # поиск среди студентов (в составе)
    p_q = (
        request.GET.get("p_q") or ""
    ).strip()  # поиск среди преподавателей (в составе)
    page = max(int(request.GET.get("page", 1) or 1), 1)
    offset = (page - 1) * PAGE_SIZE

    with connection.cursor() as cur:
        # Проект
        cur.execute(
            "SELECT project_id, project_name FROM projects WHERE project_id=%s",
            [project_id],
        )
        r = cur.fetchone()
        if not r:
            raise Http404("Проект не найден")
        project = {"project_id": r[0], "project_name": r[1]}

        # Текущие студенты (с фильтром)
        cur.execute(
            """
            SELECT m.id, m.role_in_team, m.joined_at, m.left_at,
                   s.student_id, u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                   s.group_number, s.faculty
            FROM project_members m
            JOIN students s ON s.student_id = m.member_student
            JOIN users u    ON u.user_id    = s.user_id
            WHERE m.project_id = %s
              AND m.member_student IS NOT NULL
              AND (%s = '' OR u.last_name ILIKE '%%'||%s||'%%'
                           OR u.first_name ILIKE '%%'||%s||'%%'
                           OR s.group_number ILIKE '%%'||%s||'%%'
                           OR u.login ILIKE '%%'||%s||'%%')
            ORDER BY fio
            """,
            [project_id, s_q, s_q, s_q, s_q, s_q],
        )
        students = _fetchall_dict(cur)

        # Текущие преподаватели (с фильтром)
        cur.execute(
            """
            SELECT m.id, m.role_in_team, m.joined_at, m.left_at,
                   p.professor_id, u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                   p.department, p.faculty
            FROM project_members m
            JOIN professors p ON p.professor_id = m.member_prof
            JOIN users u      ON u.user_id      = p.user_id
            WHERE m.project_id = %s
              AND m.member_prof IS NOT NULL
              AND (%s = '' OR u.last_name ILIKE '%%'||%s||'%%'
                           OR u.first_name ILIKE '%%'||%s||'%%'
                           OR p.department ILIKE '%%'||%s||'%%'
                           OR u.login ILIKE '%%'||%s||'%%')
            ORDER BY fio
            """,
            [project_id, p_q, p_q, p_q, p_q, p_q],
        )
        profs = _fetchall_dict(cur)

        # Кандидаты: исключаем всех, кто уже АКТИВЕН в проекте (left_at IS NULL)
        candidates = []
        if sr == "student":
            cur.execute(
                """
                SELECT s.student_id AS id,
                       u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                       s.group_number, s.faculty
                FROM students s
                JOIN users u ON u.user_id = s.user_id
                WHERE (%s = '' OR u.last_name ILIKE '%%'||%s||'%%'
                               OR u.first_name ILIKE '%%'||%s||'%%'
                               OR s.group_number ILIKE '%%'||%s||'%%'
                               OR u.login ILIKE '%%'||%s||'%%')
                  AND NOT EXISTS (
                      SELECT 1 FROM project_members m
                      WHERE m.project_id = %s
                        AND m.member_student = s.student_id
                        AND m.left_at IS NULL
                  )
                ORDER BY fio
                LIMIT %s OFFSET %s
                """,
                [c_q, c_q, c_q, c_q, c_q, project_id, PAGE_SIZE, offset],
            )
            candidates = [
                {"id": rid, "label": f"{fio} — гр. {grp} ({fac})"}
                for (rid, fio, grp, fac) in cur.fetchall()
            ]
        else:
            cur.execute(
                """
                SELECT p.professor_id AS id,
                       u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                       p.department, p.faculty
                FROM professors p
                JOIN users u ON u.user_id = p.user_id
                WHERE (%s = '' OR u.last_name ILIKE '%%'||%s||'%%'
                               OR u.first_name ILIKE '%%'||%s||'%%'
                               OR p.department ILIKE '%%'||%s||'%%'
                               OR u.login ILIKE '%%'||%s||'%%')
                  AND NOT EXISTS (
                      SELECT 1 FROM project_members m
                      WHERE m.project_id = %s
                        AND m.member_prof = p.professor_id
                        AND m.left_at IS NULL
                  )
                ORDER BY fio
                LIMIT %s OFFSET %s
                """,
                [c_q, c_q, c_q, c_q, c_q, project_id, PAGE_SIZE, offset],
            )
            candidates = [
                {"id": rid, "label": f"{fio} — {dept} ({fac})"}
                for (rid, fio, dept, fac) in cur.fetchall()
            ]

    ctx = {
        "project": project,
        "students": students,
        "profs": profs,
        "sr": sr,
        "c_q": c_q,
        "s_q": s_q,
        "p_q": p_q,
        "page": page,
        "has_next": len(candidates) == PAGE_SIZE,
        "candidates": candidates,
    }
    return render(request, "adminboard/project_members_admin.html", ctx)


@login_required
@require_POST
def member_add(request, project_id: int):
    if not _is_admin(request):
        return HttpResponseForbidden("Только админ")
    kind = (request.POST.get("kind") or "").lower()  # student/professor
    pid = request.POST.get("person_id") or ""
    role = (request.POST.get("role_in_team") or "").strip() or None
    if kind not in ("student", "professor") or not pid.isdigit():
        messages.error(request, "Укажите корректного участника")
        return redirect("adminboard:project-members-admin", project_id=project_id)
    with connection.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM project_members WHERE project_id=%s AND "
            + ("member_student=%s" if kind == "student" else "member_prof=%s"),
            [project_id, pid],
        )
        if cur.fetchone():
            messages.warning(request, "Участник уже в проекте")
        else:
            cur.execute(
                f"INSERT INTO project_members (project_id, {'member_student' if kind == 'student' else 'member_prof'}, role_in_team) VALUES (%s,%s,%s)",
                [project_id, pid, role],
            )
            messages.success(request, "Участник добавлен")
    return redirect("adminboard:project-members-admin", project_id=project_id)


@login_required
@require_POST
def member_update(request, member_id: int):
    # только роль редактируем, left_at руками не трогаем
    if not _is_admin(request):
        return HttpResponseForbidden("Только админ")
    role = (request.POST.get("role_in_team") or "").strip() or None
    with connection.cursor() as cur:
        cur.execute(
            "UPDATE project_members SET role_in_team=%s WHERE id=%s", [role, member_id]
        )
        cur.execute("SELECT project_id FROM project_members WHERE id=%s", [member_id])
        project_id = cur.fetchone()[0]
    messages.success(request, "Роль обновлена")
    return redirect("adminboard:project-members-admin", project_id=project_id)


@login_required
@require_POST
def member_leave(request, member_id: int):
    # логическое исключение: ставим left_at = now()
    if not _is_admin(request):
        return HttpResponseForbidden("Только админ")
    with connection.cursor() as cur:
        cur.execute("SELECT project_id FROM project_members WHERE id=%s", [member_id])
        r = cur.fetchone()
        project_id = r[0] if r else None
        cur.execute("SELECT fn_member_leave(%s)", [member_id])
    messages.info(request, "Участник исключён (закрыта дата участия)")
    return redirect("adminboard:project-members-admin", project_id=project_id or 0)
