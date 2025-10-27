-- Три прикладные роли
DO $$ BEGIN CREATE ROLE role_student NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE role_professor NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE role_admin NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- Технический пользователь приложения
DO $$ BEGIN CREATE ROLE app_user LOGIN PASSWORD 'dev_password'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT role_student, role_professor, role_admin TO app_user; -- позволит SET ROLE


-- Базовые права (пример)
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
GRANT SELECT ON users TO role_admin; -- пример
GRANT SELECT,INSERT,UPDATE ON projects, tasks, reports TO role_professor;
GRANT SELECT,INSERT ON reports TO role_student;
GRANT SELECT ON projects, tasks TO role_student;
-- и т.д. (уточняется по операциям)
