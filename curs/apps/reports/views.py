from django.contrib.auth.decorators import login_required
from django.views.decorators.http import require_POST
from django.shortcuts import redirect
from django.http import Http404, HttpResponseForbidden
from django.contrib import messages
from django.db import connection
from django.core.files.storage import default_storage
from uuid import uuid4
import json

MAX_UPLOAD = 10 * 1024 * 1024  # 10 MB
ALLOWED_EXT = {"pdf", "doc", "docx", "txt", "md", "png", "jpg", "jpeg", "zip"}


# --- helpers ---------------------------------------------------------------


def _get_student_id_by_user(user_id: int):
    with connection.cursor() as cur:
        cur.execute("SELECT student_id FROM students WHERE user_id=%s", [user_id])
        row = cur.fetchone()
        return row[0] if row else None


def _get_professor_id_by_user(user_id: int):
    with connection.cursor() as cur:
        cur.execute("SELECT professor_id FROM professors WHERE user_id=%s", [user_id])
        row = cur.fetchone()
        return row[0] if row else None


def _task_core(task_id: int):
    """Вернёт (project_id, executor_student) или (None, None)."""
    with connection.cursor() as cur:
        cur.execute(
            "SELECT project_id, executor_student FROM tasks WHERE task_id=%s", [task_id]
        )
        row = cur.fetchone()
        return (row[0], row[1]) if row else (None, None)


def _student_on_project(student_id: int, project_id: int) -> bool:
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT 1 FROM project_members
            WHERE project_id=%s AND member_student=%s
            """,
            [project_id, student_id],
        )
        return cur.fetchone() is not None


def _prof_on_project(professor_id: int, project_id: int) -> bool:
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT 1 FROM project_members
            WHERE project_id=%s AND member_prof=%s
            """,
            [project_id, professor_id],
        )
        return cur.fetchone() is not None


def _project_id_by_task(task_id: int) -> int:
    with connection.cursor() as cur:
        cur.execute("SELECT project_id FROM tasks WHERE task_id=%s", [task_id])
        row = cur.fetchone()
        return row[0] if row else 0


def _insert_log(
    action: str, actor_user_id: int | None, admin_id: int | None, details: dict
):
    """Безопасное логирование: при любых ошибках прав/схемы просто выходим."""
    details_json = json.dumps(details, ensure_ascii=False)
    try:
        with connection.cursor() as cur:
            cur.execute(
                """
                INSERT INTO admin_logs (admin_id, admin_action, log_created_at, actor_user_id, details)
                VALUES (%s, %s, now(), %s, %s::jsonb)
                """,
                [admin_id, action, actor_user_id, details_json],
            )
    except Exception as e:
        # Сбросим соединение из "ошибочного" состояния и не мешаем основному сценарию
        try:
            connection.rollback()
        except Exception:
            pass
        # Если хочешь, можно залогировать в stdout: print(f"admin_log skipped: {e}")
        return


# --- endpoints -------------------------------------------------------------


@require_POST
@login_required
def submit_report(request, task_id: int):
    # Только студент может сдавать отчёт
    if getattr(request.user, "role", None) != "STUDENT":
        return HttpResponseForbidden("Только студент может сдавать отчёт")

    # Текущий студент
    user_pk = getattr(request.user, "user_id", None) or request.user.pk
    sid = _get_student_id_by_user(user_pk)
    if not sid:
        raise Http404("Студент не найден")

    # Задача и назначенный исполнитель
    project_id, executor_sid = _task_core(task_id)
    if not project_id:
        raise Http404("Задача не найдена")

    # Запрещаем сдачу по архивной задаче/проекту
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT 1
            FROM tasks t
            JOIN projects p ON p.project_id = t.project_id
            WHERE t.task_id=%s
              AND COALESCE(t.archived_at, p.archived_at) IS NULL
            LIMIT 1
        """,
            [task_id],
        )
        if not cur.fetchone():
            messages.error(
                request, "Задача или проект в архиве — сдача отчёта недоступна."
            )
            return redirect("projects:project-detail", project_id=project_id)

    # Право сдачи: если исполнитель назначен — только он; иначе — любой студент-участник проекта
    if executor_sid and executor_sid != sid:
        return HttpResponseForbidden("Вы не исполнитель этой задачи")
    if not executor_sid and not _student_on_project(sid, project_id):
        return HttpResponseForbidden("Вы не являетесь участником проекта")

    # Данные формы: файл ИЛИ ссылка (строго одно из двух)
    file = request.FILES.get("file")
    external_url = (request.POST.get("external_url") or "").strip() or None

    if not file and not external_url:
        messages.error(request, "Нужно приложить файл или указать ссылку")
        return redirect("projects:project-detail", project_id=project_id)
    if file and external_url:
        messages.error(request, "Либо файл, либо ссылка — не оба сразу")
        return redirect("projects:project-detail", project_id=project_id)

    # Валидация и сохранение файла (если есть)
    stored_path = None
    if file:
        if file.size > MAX_UPLOAD:
            messages.error(request, "Файл больше 10 MB")
            return redirect("projects:project-detail", project_id=project_id)
        ext = file.name.rsplit(".", 1)[-1].lower() if "." in file.name else "bin"
        if ext not in ALLOWED_EXT:
            messages.error(request, f"Недопустимое расширение: .{ext}")
            return redirect("projects:project-detail", project_id=project_id)

        stored_path = f"uploads/reports/{uuid4()}.{ext}"
        # сохраняем потоково (как у тебя было)
        with default_storage.open(stored_path, "wb+") as dst:
            for chunk in file.chunks():
                dst.write(chunk)

    # Пишем отчёт в БД
    try:
        with connection.cursor() as cur:
            cur.execute(
                """
                INSERT INTO reports (task_id, student_id, file_path, external_url, status, submitted_at)
                VALUES (%s, %s, %s, %s, 'submitted', now())
                """,
                [task_id, sid, stored_path, external_url],
            )
    except DatabaseError as e:
        # Наиболее частый случай при SET ROLE — нет прав на таблицу/sequence
        try:
            connection.rollback()
        except Exception:
            pass
        messages.error(request, f"Не смог сохранить отчёт: {e}")
        return redirect("projects:project-detail", project_id=project_id)

    # Логирование: не должно мешать основному сценарию, поэтому «тихо»
    try:
        _insert_log(
            action="REPORT_SUBMIT",
            actor_user_id=user_pk,
            admin_id=None,
            details={
                "task_id": task_id,
                "project_id": project_id,
                "student_id": sid,
                "file_path": stored_path,
                "external_url": external_url,
            },
        )
    except Exception:
        try:
            connection.rollback()
        except Exception:
            pass
        # пропускаем лог при любой ошибке прав/схемы

    messages.success(request, "Отчёт отправлен")
    return redirect("projects:project-detail", project_id=project_id)


@require_POST
@login_required
def moderate_task(request, task_id: int):
    # только преподаватель (по ТЗ проверка «со стороны преподавателя»)
    if getattr(request.user, "role", None) != "PROFESSOR":
        return HttpResponseForbidden("Недостаточно прав")

    pid = _get_professor_id_by_user(
        getattr(request.user, "user_id", None) or request.user.pk
    )
    if not pid:
        raise Http404("Преподаватель не найден")

    project_id, _ = _task_core(task_id)
    if not project_id:
        raise Http404("Задача не найдена")

    if not _prof_on_project(pid, project_id):
        return HttpResponseForbidden("Вы не являетесь преподавателем проекта")

    # последний отчёт по задаче
    with connection.cursor() as cur:
        cur.execute(
            """
            SELECT report_id FROM reports
            WHERE task_id=%s
            ORDER BY submitted_at DESC
            LIMIT 1
            """,
            [task_id],
        )
        row = cur.fetchone()
    if not row:
        messages.error(request, "Нет отчётов для модерации")
        return redirect("projects:project-detail", project_id=project_id)

    report_id = row[0]
    action = request.POST.get("action")
    comment = (request.POST.get("comment") or "").strip()

    if action == "approve":
        with connection.cursor() as cur:
            cur.execute(
                """
                UPDATE reports
                SET status='approved', reviewed_at=now(), reviewed_by_prof=%s
                WHERE report_id=%s
                """,
                [pid, report_id],
            )
        _insert_log(
            action="REPORT_APPROVE",
            actor_user_id=getattr(request.user, "user_id", None) or request.user.pk,
            admin_id=None,
            details={
                "report_id": report_id,
                "task_id": task_id,
                "project_id": project_id,
            },
        )
        messages.success(request, "Отчёт принят")

    elif action == "needs_fix":
        if not comment:
            messages.error(request, "Нужен комментарий при возврате")
            return redirect("projects:project-detail", project_id=project_id)
        with connection.cursor() as cur:
            cur.execute(
                """
                UPDATE reports
                SET status='needs_fix', reviewed_at=now(), reviewed_by_prof=%s
                WHERE report_id=%s
                """,
                [pid, report_id],
            )
        _insert_log(
            action="REPORT_COMMENT",
            actor_user_id=getattr(request.user, "user_id", None) or request.user.pk,
            admin_id=None,
            details={
                "report_id": report_id,
                "task_id": task_id,
                "project_id": project_id,
                "comment": comment,
            },
        )
        messages.info(request, "Отчёт возвращён на доработку")

    else:
        messages.error(request, "Неизвестное действие")

    return redirect("projects:project-detail", project_id=project_id)
