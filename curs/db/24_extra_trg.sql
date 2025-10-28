-- Архивировать задачи и участников при архиве проекта
CREATE OR REPLACE FUNCTION fn_archive_children_on_project_archive()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Участники
  UPDATE project_members pm
     SET archived_at = COALESCE(pm.archived_at, COALESCE(NEW.release_date, now()))
   WHERE pm.project_id = NEW.project_id
     AND pm.archived_at IS NULL;

  -- Задачи
  UPDATE tasks t
     SET archived_at = COALESCE(t.archived_at, now())
   WHERE t.project_id = NEW.project_id
     AND t.archived_at IS NULL;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_archive_children_on_project_archive ON projects;
CREATE TRIGGER trg_archive_children_on_project_archive
AFTER UPDATE OF project_status ON projects
FOR EACH ROW
WHEN (NEW.project_status = 'archived' AND (OLD.project_status IS DISTINCT FROM 'archived'))
EXECUTE FUNCTION fn_archive_children_on_project_archive();

-- Синхронная разархивация детей при разархивировании проекта
CREATE OR REPLACE FUNCTION fn_unarchive_children_on_project_unarchive()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Проект разархивирован
  IF (OLD.archived_at IS NOT NULL AND NEW.archived_at IS NULL)
     OR (OLD.project_status = 'archived' AND NEW.project_status IN ('active','paused')) THEN

    UPDATE project_members SET archived_at = NULL
     WHERE project_id = NEW.project_id AND archived_at IS NOT NULL;

    UPDATE tasks SET archived_at = NULL
     WHERE project_id = NEW.project_id AND archived_at IS NOT NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_unarchive_children_on_project_unarchive ON projects;
CREATE TRIGGER trg_unarchive_children_on_project_unarchive
AFTER UPDATE OF archived_at, project_status ON projects
FOR EACH ROW
EXECUTE FUNCTION fn_unarchive_children_on_project_unarchive();

-- Запрет разархивации задач/участников, если проект всё ещё в архиве
CREATE OR REPLACE FUNCTION fn_guard_child_unarchive_when_project_archived()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_is_archived boolean;
BEGIN
  IF NEW.archived_at IS NULL THEN
    SELECT is_archived INTO v_is_archived FROM projects WHERE project_id =
      CASE WHEN TG_TABLE_NAME = 'tasks' THEN NEW.project_id
           WHEN TG_TABLE_NAME = 'project_members' THEN NEW.project_id
      END;
    IF v_is_archived THEN
      RAISE EXCEPTION 'Cannot unarchive % when parent project is archived', TG_TABLE_NAME;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_guard_unarchive_tasks ON tasks;
CREATE TRIGGER trg_guard_unarchive_tasks
BEFORE UPDATE OF archived_at ON tasks
FOR EACH ROW
EXECUTE FUNCTION fn_guard_child_unarchive_when_project_archived();

DROP TRIGGER IF EXISTS trg_guard_unarchive_members ON project_members;
CREATE TRIGGER trg_guard_unarchive_members
BEFORE UPDATE OF archived_at ON project_members
FOR EACH ROW
EXECUTE FUNCTION fn_guard_child_unarchive_when_project_archived();
