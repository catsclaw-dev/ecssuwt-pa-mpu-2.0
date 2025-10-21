BEGIN;

-- базовый доступ к схеме
GRANT USAGE ON SCHEMA public TO role_student, role_professor, role_admin;

-- чтение основных таблиц
GRANT SELECT ON
  users,
  projects,
  project_members,
  students,
  professors,
  tasks,
  reports,
  application_details,
  project_applications
TO role_student, role_professor, role_admin;

-- если есть таблица расписания — дать права на чтение
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='project_schedule'
  ) THEN
    EXECUTE 'GRANT SELECT ON project_schedule TO role_student, role_professor, role_admin';
  END IF;
END $$;

-- студент сдаёт отчёт → INSERT в reports (+ доступ к sequence)
GRANT INSERT ON reports TO role_student;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_student;

-- преподаватель (и админ) проверяет отчёт → UPDATE в reports
GRANT UPDATE (status, reviewed_by_prof, reviewed_at) ON reports TO role_professor, role_admin;

-- журналируем действия (submit/approve/needs_fix) → INSERT в admin_logs
GRANT INSERT ON admin_logs TO role_student, role_professor, role_admin;

COMMIT;
