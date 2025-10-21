BEGIN;

GRANT USAGE ON SCHEMA public TO role_student, role_professor, role_admin;

GRANT INSERT, UPDATE ON projects TO role_admin;
GRANT INSERT, UPDATE ON tasks    TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_admin;

GRANT INSERT, UPDATE ON tasks TO role_professor;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='project_schedule') THEN
    EXECUTE 'GRANT INSERT, UPDATE ON project_schedule TO role_professor, role_admin';
  END IF;
END $$;

COMMIT;
