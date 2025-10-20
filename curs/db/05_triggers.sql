DROP TRIGGER IF EXISTS trg_projects_auto_archive ON projects;
CREATE TRIGGER trg_projects_auto_archive
BEFORE INSERT OR UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION fn_auto_archive_projects();
