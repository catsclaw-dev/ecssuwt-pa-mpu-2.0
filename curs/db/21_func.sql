-- =========================
-- УТИЛИТЫ ДЛЯ ДАТ/АРХИВАЦИИ
-- =========================

-- Универсальный помощник: если статус становится 'archived' и нет archived_at — проставить.
CREATE OR REPLACE FUNCTION _touch_archived_at(p_status project_status, p_archived_at TIMESTAMPTZ)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF p_status = 'archived' AND p_archived_at IS NULL THEN
    RETURN now();
  END IF;
  RETURN p_archived_at;
END $$;

-- Запрет обновления "архивированной" строки (кроме явного разархива/арха-полей).
CREATE OR REPLACE FUNCTION fn_block_updates_on_archived()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_tbl text := TG_TABLE_NAME;
BEGIN
  -- Если в строке есть archived_at и он уже установлен,
  -- запрещаем UPDATE, за исключением операций UNARCHIVE.
  IF (OLD.archived_at IS NOT NULL) THEN
    -- Разрешим UPDATE только если NEW.archived_at стал NULL (unarchive)
    -- или если меняются только системные «безопасные» поля (примерно).
    IF NEW.archived_at IS DISTINCT FROM OLD.archived_at AND NEW.archived_at IS NULL THEN
      RETURN NEW; -- unarchive — можно
    END IF;

    RAISE EXCEPTION 'Cannot modify archived row in % (id=%)', v_tbl,
      COALESCE(OLD.id, COALESCE(OLD.project_id, COALESCE(OLD.task_id, COALESCE(OLD.report_id, OLD.user_id))));
  END IF;

  RETURN NEW;
END $$;

-- =========================
-- PROJECTS: АВТОАРХИВ И КОНСИСТЕНТНОСТЬ
-- =========================

-- Автоархив по release_date при вставке/обновлении
CREATE OR REPLACE FUNCTION fn_projects_auto_archive()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- Если указан release_date в прошлом — переводим статус в archived
  IF NEW.release_date IS NOT NULL AND NEW.release_date < now() THEN
    NEW.project_status := 'archived';
  END IF;

  -- Если статус archived — обеспечим archived_at
  NEW.archived_at := _touch_archived_at(NEW.project_status, NEW.archived_at);

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_projects_auto_archive ON projects;
CREATE TRIGGER trg_projects_auto_archive
BEFORE INSERT OR UPDATE ON projects
FOR EACH ROW
EXECUTE FUNCTION fn_projects_auto_archive();

-- Массовая проставка left_at участникам при архиве проекта
CREATE OR REPLACE FUNCTION fn_members_left_at_on_project_archive()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.project_status = 'archived' AND OLD.project_status <> 'archived' THEN
    UPDATE project_members m
    SET left_at = COALESCE(NEW.release_date, now())
    WHERE m.project_id = NEW.project_id
      AND m.left_at IS NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_members_left_at_on_project_archive ON projects;
CREATE TRIGGER trg_members_left_at_on_project_archive
AFTER UPDATE OF project_status ON projects
FOR EACH ROW
EXECUTE FUNCTION fn_members_left_at_on_project_archive();

-- Блокировка изменений в архивированном проекте
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_project ON projects;
CREATE TRIGGER trg_block_updates_on_archived_project
BEFORE UPDATE ON projects
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- PROJECT MEMBERS: МЯГКОЕ ИСКЛЮЧЕНИЕ
-- =========================
CREATE OR REPLACE FUNCTION fn_member_leave(p_member_id BIGINT, p_left_at TIMESTAMPTZ DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_members
  SET left_at = COALESCE(p_left_at, now())
  WHERE id = p_member_id AND left_at IS NULL;
END $$;

-- Блокировка изменений в архивированных участниках
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_member ON project_members;
CREATE TRIGGER trg_block_updates_on_archived_member
BEFORE UPDATE ON project_members
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- APPLICATION → PROJECT: УТВЕРЖДЕНИЕ ЗАЯВКИ
-- =========================
CREATE OR REPLACE FUNCTION fn_project_app_approve(app_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  prj_id BIGINT;
BEGIN
  -- Подтвердим заявку (включая метку времени)
  UPDATE project_applications
  SET status='approved', act_at=now()
  WHERE application_id = app_id;

  -- Создадим проект из заявки (если не создан)
  INSERT INTO projects (project_name, project_description, application_id, specialization)
  SELECT ad.name, ad.goal, app.application_id, ad.specialization
  FROM project_applications app
  JOIN application_details ad ON ad.ap_info_id = app.ap_info_id
  WHERE app.application_id = app_id
    AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.application_id = app.application_id)
  RETURNING project_id INTO prj_id;

  -- Если проект уже существовал — вернуть его id
  IF prj_id IS NULL THEN
    SELECT p.project_id INTO prj_id FROM projects p WHERE p.application_id = app_id;
  END IF;

  RETURN prj_id;
END $$;

-- =========================
-- REPORTS: ВАЛИДАЦИЯ ПОЛЕЙ РЕВЬЮ
-- =========================
-- Требования:
--  - status='submitted' → не должно быть reviewed_by_prof/reviewed_at
--  - status IN ('approved','needs_fix') → reviewed_by_prof и reviewed_at ОБЯЗАТЕЛЬНЫ
--  - status='needs_fix' → review_comment ОБЯЗАТЕЛЕН (дублируем CHECK триггером для понятного текста ошибки)

CREATE OR REPLACE FUNCTION fn_reports_validate_review_fields()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'submitted' THEN
    IF NEW.reviewed_by_prof IS NOT NULL OR NEW.reviewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'submitted reports must not have reviewer fields';
    END IF;
  ELSE
    -- approved / needs_fix
    IF NEW.reviewed_by_prof IS NULL OR NEW.reviewed_at IS NULL THEN
      RAISE EXCEPTION 'reviewed reports must contain reviewer and reviewed_at';
    END IF;
    IF NEW.status = 'needs_fix' AND (NEW.review_comment IS NULL OR btrim(NEW.review_comment) = '') THEN
      RAISE EXCEPTION 'needs_fix requires non-empty review_comment';
    END IF;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_reports_validate_review_fields_ins ON reports;
CREATE TRIGGER trg_reports_validate_review_fields_ins
BEFORE INSERT ON reports
FOR EACH ROW
EXECUTE FUNCTION fn_reports_validate_review_fields();

DROP TRIGGER IF EXISTS trg_reports_validate_review_fields_upd ON reports;
CREATE TRIGGER trg_reports_validate_review_fields_upd
BEFORE UPDATE OF status, reviewed_by_prof, reviewed_at, review_comment ON reports
FOR EACH ROW
EXECUTE FUNCTION fn_reports_validate_review_fields();

-- Блокировка изменений в архивированных отчётах
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_report ON reports;
CREATE TRIGGER trg_block_updates_on_archived_report
BEFORE UPDATE ON reports
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- TASK STATUS: АВТОАКТУАЛИЗАЦИЯ ПО ОТЧЁТАМ
-- =========================
-- Логика (последний по submitted_at отчёт):
--   approved  -> task.done
--   needs_fix -> task.in_review
--   submitted -> task.in_review
CREATE OR REPLACE FUNCTION fn_sync_task_status_from_reports(p_task_id BIGINT)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_status report_status;
BEGIN
  SELECT r.status
  INTO v_status
  FROM reports r
  WHERE r.task_id = p_task_id AND archived_at = NULL
  ORDER BY r.submitted_at DESC, r.report_id DESC
  LIMIT 1;

  IF v_status IS NULL THEN
    -- нет отчётов — не трогаем
    RETURN;
  END IF;

  IF v_status = 'approved' THEN
    UPDATE tasks SET task_status='done' WHERE task_id = p_task_id AND task_status <> 'done';
  ELSE
    -- submitted / needs_fix
    UPDATE tasks SET task_status='in_review' WHERE task_id = p_task_id AND task_status <> 'in_review';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_after_report_upsert_sync_task()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM fn_sync_task_status_from_reports(NEW.task_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_after_report_insert_sync_task ON reports;
CREATE TRIGGER trg_after_report_insert_sync_task
AFTER INSERT ON reports
FOR EACH ROW
EXECUTE FUNCTION fn_after_report_upsert_sync_task();

DROP TRIGGER IF EXISTS trg_after_report_update_sync_task ON reports;
CREATE TRIGGER trg_after_report_update_sync_task
AFTER UPDATE OF status, submitted_at ON reports
FOR EACH ROW
EXECUTE FUNCTION fn_after_report_upsert_sync_task();

-- =========================
-- TASKS: БЛОКИРОВКА ДЛЯ АРХИВНЫХ
-- =========================
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_task ON tasks;
CREATE TRIGGER trg_block_updates_on_archived_task
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- APPLICATIONS / DETAILS: МЯГКАЯ АРХИВАЦИЯ И ЗАЩИТА
-- =========================
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_app ON project_applications;
CREATE TRIGGER trg_block_updates_on_archived_app
BEFORE UPDATE ON project_applications
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

DROP TRIGGER IF EXISTS trg_block_updates_on_archived_appd ON application_details;
CREATE TRIGGER trg_block_updates_on_archived_appd
BEFORE UPDATE ON application_details
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- USERS/STUDENTS/PROFESSORS: ЗАЩИТА
-- =========================
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_user ON users;
CREATE TRIGGER trg_block_updates_on_archived_user
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

DROP TRIGGER IF EXISTS trg_block_updates_on_archived_student ON students;
CREATE TRIGGER trg_block_updates_on_archived_student
BEFORE UPDATE ON students
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

DROP TRIGGER IF EXISTS trg_block_updates_on_archived_prof ON professors;
CREATE TRIGGER trg_block_updates_on_archived_prof
BEFORE UPDATE ON professors
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();

-- =========================
-- ПУБЛИЧНЫЕ API ДЛЯ АРХИВАЦИИ / РАЗАРХИВАЦИИ
-- =========================
-- Проекты
CREATE OR REPLACE FUNCTION fn_archive_project(p_project_id BIGINT, p_archived_at TIMESTAMPTZ DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE projects
  SET project_status='archived',
      archived_at = COALESCE(archived_at, COALESCE(p_archived_at, now()))
  WHERE project_id = p_project_id;

  -- синхронно закрыть участников без left_at
  UPDATE project_members
  SET left_at = COALESCE(p_archived_at, now())
  WHERE project_id = p_project_id AND left_at IS NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_unarchive_project(p_project_id BIGINT)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE projects
  SET project_status='active',
      archived_at = NULL
  WHERE project_id = p_project_id;
END $$;

-- Участник проекта
CREATE OR REPLACE FUNCTION fn_archive_member(p_member_id BIGINT, p_archived_at TIMESTAMPTZ DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_members
  SET archived_at = COALESCE(archived_at, COALESCE(p_archived_at, now()))
  WHERE id = p_member_id;

  PERFORM fn_member_leave(p_member_id, p_archived_at);
END $$;

CREATE OR REPLACE FUNCTION fn_unarchive_member(p_member_id BIGINT)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_members
  SET archived_at = NULL
  WHERE id = p_member_id;
END $$;

-- Заявка и детали
CREATE OR REPLACE FUNCTION fn_archive_application(p_application_id BIGINT, p_archived_at TIMESTAMPTZ DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_applications
  SET archived_at = COALESCE(archived_at, COALESCE(p_archived_at, now()))
  WHERE application_id = p_application_id;
END $$;

CREATE OR REPLACE FUNCTION fn_unarchive_application(p_application_id BIGINT)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_applications
  SET archived_at = NULL
  WHERE application_id = p_application_id;
END $$;

-- Отчёт
CREATE OR REPLACE FUNCTION fn_archive_report(p_report_id BIGINT, p_archived_at TIMESTAMPTZ DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_task BIGINT;
BEGIN
  UPDATE reports
  SET archived_at = COALESCE(archived_at, COALESCE(p_archived_at, now()))
  WHERE report_id = p_report_id
  RETURNING task_id INTO v_task;

  -- при архивации отчёта пересчитать статус задачи по оставшимся отчётам
  IF v_task IS NOT NULL THEN
    PERFORM fn_sync_task_status_from_reports(v_task);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_unarchive_report(p_report_id BIGINT)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_task BIGINT;
BEGIN
  UPDATE reports
  SET archived_at = NULL
  WHERE report_id = p_report_id
  RETURNING task_id INTO v_task;

  IF v_task IS NOT NULL THEN
    PERFORM fn_sync_task_status_from_reports(v_task);
  END IF;
END $$;

-- =========================
-- PROJECT_SCHEDULE: ЗАЩИТА ДЛЯ АРХИВА
-- =========================
DROP TRIGGER IF EXISTS trg_block_updates_on_archived_schedule ON project_schedule;
CREATE TRIGGER trg_block_updates_on_archived_schedule
BEFORE UPDATE ON project_schedule
FOR EACH ROW
EXECUTE FUNCTION fn_block_updates_on_archived();
