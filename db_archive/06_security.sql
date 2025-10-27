-- 06_security.sql  (вариант под pcadmin)

-- 1) Групповые роли (без логина), для SET ROLE из middleware
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
END $$;

-- 2) Логин-роль приложения: pcadmin — член всех групповых ролей
GRANT role_student   TO pcadmin;
GRANT role_professor TO pcadmin;
GRANT role_admin     TO pcadmin;

-- 3) Схема public — владелец и права
ALTER SCHEMA public OWNER TO pcadmin;
GRANT USAGE, CREATE ON SCHEMA public TO pcadmin;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- 4) Права на ИМЕЮЩИЕСЯ объекты
-- Таблицы
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT SELECT, INSERT, UPDATE            ON projects, tasks, reports           TO role_professor;
GRANT SELECT                            ON users, projects, tasks, reports    TO role_student;
GRANT INSERT                            ON reports                             TO role_student;

-- Последовательности (нужны для INSERT с DEFAULT nextval(...))
GRANT USAGE ON SCHEMA public TO role_admin, role_professor, role_student;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_professor;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_student;

-- (Функции по умолчанию EXECUTE для PUBLIC; если хочешь закрыть, можно отдельно REVOKE/GRANT EXECUTE)

-- 5) ДЕФОЛТНЫЕ права для БУДУЩИХ объектов, которые будет создавать pcadmin
ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES   TO role_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE        ON TABLES   TO role_professor;
ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT SELECT                         ON TABLES   TO role_student;

ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO role_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO role_professor;
ALTER DEFAULT PRIVILEGES FOR ROLE pcadmin IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO role_student;
