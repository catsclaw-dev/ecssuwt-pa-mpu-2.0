-- =========================
-- РОЛИ: группы и тех.пользователь
-- =========================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='role_student') THEN
    CREATE ROLE role_student NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='role_professor') THEN
    CREATE ROLE role_professor NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='role_admin') THEN
    CREATE ROLE role_admin NOLOGIN NOINHERIT;
  END IF;

  -- Владелец объектов БД (не логин) — удобно для ALTER DEFAULT PRIVILEGES
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_owner') THEN
    CREATE ROLE app_owner NOLOGIN;
  END IF;

  -- Логин приложения; пароль — заглушка, задай свой
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='curs_pc_admin') THEN
    CREATE ROLE curs_pc_admin LOGIN PASSWORD 'change_me';
  END IF;
END $$;

-- Дадим curs_pc_admin членство в групповый ролях (для SET ROLE в middleware)
GRANT role_student, role_professor, role_admin TO curs_pc_admin;

-- =========================
-- СХЕМА
-- =========================
ALTER SCHEMA public OWNER TO app_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO role_student, role_professor, role_admin;
GRANT USAGE, CREATE ON SCHEMA public TO app_owner;


-- =========================
-- ПРАВА НА ТАБЛИЦЫ (текущие)
-- =========================

-- ADMIN: полный доступ ко всем предметным таблицам
GRANT SELECT, INSERT, UPDATE, DELETE ON
  users, admins, students, professors,
  projects, project_members,
  tasks, reports,
  application_details, project_applications,
  admin_logs,
  project_schedule
TO role_admin;

-- PROFESSOR: чтение основных таблиц + работа с задачами и ревью отчётов
GRANT SELECT ON
  users, students, professors,
  projects, project_members,
  tasks, reports,
  application_details, project_applications,
  project_schedule
TO role_professor;

GRANT SELECT ON project_members TO role_student;

GRANT INSERT, UPDATE ON tasks, project_schedule TO role_professor;

-- Колонко-уровневый UPDATE в reports для ревью
GRANT UPDATE (status, reviewed_by_prof, reviewed_at, review_comment)
ON reports TO role_professor;

-- STUDENT: чтение и сдача отчётов
GRANT SELECT ON
  users, projects, tasks, reports,
  application_details, project_applications,
  project_schedule
TO role_student;

GRANT INSERT ON reports TO role_student;

-- Логи: писать могут все роли (читает только админ)
GRANT INSERT ON admin_logs TO role_student, role_professor, role_admin;
REVOKE SELECT     ON admin_logs FROM role_student, role_professor;
GRANT SELECT   ON admin_logs TO role_admin;

-- =========================
-- ПОСЛЕДОВАТЕЛЬНОСТИ (для INSERT с DEFAULT nextval)
-- =========================
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_professor; -- для INSERT в tasks
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_student;   -- для INSERT в reports

-- =========================
-- ДЕФОЛТНЫЕ ПРАВА ДЛЯ БУДУЩИХ ОБЪЕКТОВ (которые создаст app_owner)
-- =========================
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT ON TABLES TO role_student, role_professor;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT INSERT, UPDATE ON TABLES TO role_professor;   -- чтобы создавать/править tasks

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT INSERT ON TABLES TO role_student;             -- чтобы сдавать reports

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO role_admin, role_professor, role_student;

-- Функции по умолчанию доступны PUBLIC; сделаем явнее и безопаснее
REVOKE ALL ON FUNCTION fn_project_app_approve(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_member_leave(bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_archive_project(bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_unarchive_project(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_archive_member(bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_unarchive_member(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_archive_application(bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_unarchive_application(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_archive_report(bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_unarchive_report(bigint) FROM PUBLIC;

-- Кому можно выполнять прикладные функции
GRANT EXECUTE ON FUNCTION fn_project_app_approve(bigint)         TO role_admin, role_professor;
GRANT EXECUTE ON FUNCTION fn_member_leave(bigint, timestamptz)   TO role_admin;
GRANT EXECUTE ON FUNCTION fn_archive_project(bigint, timestamptz) TO role_admin;
GRANT EXECUTE ON FUNCTION fn_unarchive_project(bigint)           TO role_admin;
GRANT EXECUTE ON FUNCTION fn_archive_member(bigint, timestamptz) TO role_admin;
GRANT EXECUTE ON FUNCTION fn_unarchive_member(bigint)            TO role_admin;
GRANT EXECUTE ON FUNCTION fn_archive_application(bigint, timestamptz) TO role_admin;
GRANT EXECUTE ON FUNCTION fn_unarchive_application(bigint)       TO role_admin;
GRANT EXECUTE ON FUNCTION fn_archive_report(bigint, timestamptz) TO role_admin;
GRANT EXECUTE ON FUNCTION fn_unarchive_report(bigint)            TO role_admin;

-- =========================
-- ТОНКАЯ НАСТРОЙКА: отчёты
-- =========================
-- Запретим студентам UPDATE/DELETE отчётов (только INSERT), чтобы ревью контролировали преподы/админы
REVOKE UPDATE, DELETE ON reports FROM role_student;

-- Преподавателям не даём DELETE на отчёты (обычно не нужно)
REVOKE DELETE ON reports FROM role_professor;

-- =========================
-- ПРИМЕРЫ ДЛЯ MIDDLEWARE (как использовать SET ROLE)
-- =========================
-- В начале каждого запроса приложения:
--   SELECT set_config('app.current_user_id', '<id>', true); -- опциональный контекст
--   -- затем по users.role:
--   --   SET ROLE role_student;
--   --   или SET ROLE role_professor;
--   --   или SET ROLE role_admin;
-- В конце запроса:
--   RESET ROLE;

-- можно проверить текущую роль:
--   SELECT current_user, session_user, current_setting('role', true);
