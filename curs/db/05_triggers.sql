DROP TRIGGER IF EXISTS trg_projects_auto_archive ON projects;
CREATE TRIGGER trg_projects_auto_archive
BEFORE INSERT OR UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION fn_auto_archive_projects();

-- 1) Авто-установка left_at при архивировании проекта
CREATE OR REPLACE FUNCTION set_members_left_at_on_project_archive()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.project_status = 'archived' THEN
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
FOR EACH ROW EXECUTE FUNCTION set_members_left_at_on_project_archive();

-- 2) Аккуратное «исключение» участника без удаления
CREATE OR REPLACE FUNCTION fn_member_leave(p_member_id bigint, p_left_at timestamptz DEFAULT now())
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE project_members
  SET left_at = COALESCE(p_left_at, now())
  WHERE id = p_member_id AND left_at IS NULL;
END $$;

GRANT EXECUTE ON FUNCTION fn_member_leave(bigint, timestamptz) TO role_admin;
