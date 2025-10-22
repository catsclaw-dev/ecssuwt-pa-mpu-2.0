from django.contrib.auth.decorators import login_required
from django.views.decorators.http import require_http_methods
from django.shortcuts import render, redirect
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView
from django.http import Http404, HttpResponseForbidden
from django.db import connection
from django.contrib import messages
from .mixins import ProjectAccessMixin
from .repo import (
    get_student_id_by_user,
    get_professor_id_by_user,
    get_projects_for_student,
    get_projects_for_professor,
    get_projects_for_admin,
    get_project,
    get_project_members,
    get_project_progress,
    get_project_tasks_with_status,
    get_project_schedule,
)


def _prof_id_by_user(uid):
    with connection.cursor() as cur:
        cur.execute("SELECT professor_id FROM professors WHERE user_id=%s", [uid])
        r = cur.fetchone()
        return r[0] if r else None


def _is_prof_member_of_project(pid, project_id) -> bool:
    with connection.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM project_members WHERE project_id=%s AND member_prof=%s",
            [project_id, pid],
        )
        return cur.fetchone() is not None


def _student_in_project_active(user_id: int, project_id: int) -> bool:
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT 1
            FROM project_members m
            JOIN students s ON s.student_id = m.member_student
            WHERE m.project_id = %s
              AND s.user_id    = %s
              AND m.left_at IS NULL
        """,
            [project_id, user_id],
        )
        return cur.fetchone() is not None


def _is_member(user, project_id):
    uid = getattr(user, "user_id", None) or getattr(user, "pk", None)
    if not uid:
        return False
    if getattr(user, "role", "") == "ADMIN":
        return True
    with connection.cursor() as cur:
        if getattr(user, "role", "") == "STUDENT":
            cur.execute(
                """
              SELECT 1 FROM project_members m
              JOIN students s ON s.student_id = m.member_student
              WHERE m.project_id=%s AND s.user_id=%s AND m.left_at IS NULL
            """,
                [project_id, uid],
            )
        else:
            cur.execute(
                """
              SELECT 1 FROM project_members m
              JOIN professors p ON p.professor_id = m.member_prof
              WHERE m.project_id=%s AND p.user_id=%s AND m.left_at IS NULL
            """,
                [project_id, uid],
            )
        return cur.fetchone() is not None


class MyProjectsView(LoginRequiredMixin, TemplateView):
    template_name = "projects/my_projects.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user
        if user.role == "STUDENT":
            sid = get_student_id_by_user(user.user_id)
            ctx["projects"] = get_projects_for_student(sid) if sid else []
        elif user.role == "PROFESSOR":
            pid = get_professor_id_by_user(user.user_id)
            ctx["projects"] = get_projects_for_professor(pid) if pid else []
        else:  # ADMIN
            ctx["projects"] = get_projects_for_admin()
        return ctx


class ProjectDetailView(ProjectAccessMixin, LoginRequiredMixin, TemplateView):
    template_name = "projects/project_detail.html"

    def get_context_data(self, project_id: int, **kwargs):
        ctx = super().get_context_data(**kwargs)
        proj = get_project(project_id)
        if not proj:
            raise Http404("Проект не найден")
        ctx["project"] = proj
        ctx["members"] = get_project_members(project_id)
        ctx["progress"] = get_project_progress(project_id)
        ctx["tasks"] = get_project_tasks_with_status(project_id)
        ctx["schedule"] = get_project_schedule(project_id)
        return ctx


@login_required
@require_http_methods(["GET", "POST"])
def task_new(request, project_id: int):
    if request.user.role not in ("PROFESSOR", "ADMIN"):
        return HttpResponseForbidden("Недостаточно прав")

    if request.user.role == "PROFESSOR":
        pid = _prof_id_by_user(
            getattr(request.user, "user_id", None) or request.user.pk
        )
        if not pid or not _is_prof_member_of_project(pid, project_id):
            return HttpResponseForbidden("Вы не прикреплены к проекту")

    if request.method == "POST":
        name = (request.POST.get("task_name") or "").strip()
        description = (request.POST.get("task_description") or "").strip() or None
        exec_sid = request.POST.get("executor_student") or None
        deadline = request.POST.get("task_deadline") or None

        if not name:
            messages.error(request, "Название обязательно")
        else:
            try:
                with connection.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO tasks
                          (project_id, task_name, task_description, executor_student, task_status, task_deadline)
                        VALUES
                          (%s, %s, %s, %s, 'open', %s)
                        """,
                        [project_id, name, description, exec_sid, deadline],
                    )
                messages.success(request, "Задача создана")
                return redirect("projects:project-detail", project_id=project_id)
            except Exception as e:
                # покажем реальную причину, если что-то не так (например, формат даты)
                messages.error(request, f"Ошибка создания задачи: {e}")

    students = _student_choices_for_project(project_id)
    return render(
        request,
        "projects/task_new.html",
        {"project_id": project_id, "students": students},
    )


@login_required
@require_http_methods(["GET", "POST"])
def schedule_new(request, project_id: int):
    if request.user.role not in ("PROFESSOR", "ADMIN"):
        return HttpResponseForbidden("Недостаточно прав")

    if request.user.role == "PROFESSOR":
        pid = _prof_id_by_user(
            getattr(request.user, "user_id", None) or request.user.pk
        )
        if not pid or not _is_prof_member_of_project(pid, project_id):
            return HttpResponseForbidden("Вы не прикреплены к проекту")

    if request.method == "POST":
        title = (request.POST.get("title") or "").strip()
        starts_at = request.POST.get("starts_at") or None
        ends_at = request.POST.get("ends_at") or None
        location = (request.POST.get("location") or "").strip() or None
        desc = (request.POST.get("description") or "").strip() or None
        if not title or not starts_at or not ends_at:
            messages.error(request, "Заполните обязательные поля")
        else:
            try:
                with connection.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO project_schedule (project_id, title, description, starts_at, ends_at, location)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """,
                        [project_id, title, desc, starts_at, ends_at, location],
                    )
                messages.success(request, "Событие добавлено")
                return redirect("projects:project-detail", project_id=project_id)
            except Exception:
                messages.error(request, "Таблица расписания отсутствует")
    return render(request, "projects/schedule_new.html", {"project_id": project_id})


class ProjectTeamView(LoginRequiredMixin, TemplateView):
    template_name = "projects/project_team.html"

    def dispatch(self, request, project_id: int, *args, **kwargs):
        role = getattr(request.user, "role", "")
        uid = getattr(request.user, "user_id", None) or getattr(
            request.user, "pk", None
        )

        # ADMIN и любой PROFESSOR — всегда можно
        if role in ("ADMIN", "PROFESSOR"):
            return super().dispatch(request, project_id=project_id, *args, **kwargs)

        # STUDENT — только если он активный участник проекта
        if role == "STUDENT" and uid and _student_in_project_active(uid, project_id):
            return super().dispatch(request, project_id=project_id, *args, **kwargs)

        return render(
            request,
            "403.html",
            {
                "title": "Нет доступа",
                "message": "Страница доступна преподавателям, администратору и студентам-участникам проекта.",
            },
            status=403,
        )

    def get_context_data(self, project_id: int, **kwargs):
        ctx = super().get_context_data(**kwargs)
        with connection.cursor() as cur:
            cur.execute(
                "SELECT project_id, project_name FROM projects WHERE project_id=%s",
                [project_id],
            )
            r = cur.fetchone()
            ctx["project"] = {"project_id": r[0], "project_name": r[1]} if r else {}

            cur.execute(
                """
              SELECT u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                     'student' AS kind, m.role_in_team, m.joined_at, m.left_at, s.group_number AS extra
              FROM project_members m
              JOIN students s ON s.student_id = m.member_student
              JOIN users u    ON u.user_id    = s.user_id
              WHERE m.project_id = %s
              UNION ALL
              SELECT u.last_name||' '||u.first_name||COALESCE(' '||u.middle_name,'') AS fio,
                     'professor' AS kind, m.role_in_team, m.joined_at, m.left_at, p.department AS extra
              FROM project_members m
              JOIN professors p ON p.professor_id = m.member_prof
              JOIN users u      ON u.user_id      = p.user_id
              WHERE m.project_id = %s
              ORDER BY kind, fio
            """,
                [project_id, project_id],
            )
            cols = [c[0] for c in cur.description]
            ctx["members"] = [dict(zip(cols, r)) for r in cur.fetchall()]
        return ctx
