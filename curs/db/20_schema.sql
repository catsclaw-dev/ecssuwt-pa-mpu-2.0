CREATE EXTENSION IF NOT EXISTS citext;

DO $$ BEGIN
  CREATE TYPE project_status AS ENUM ('active','paused','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE task_status AS ENUM ('open','in_review','done');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE report_status AS ENUM ('submitted','needs_fix','approved');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE application_status AS ENUM ('pending','approved','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- USERS AND ROLES
CREATE TABLE IF NOT EXISTS users (
  user_id         BIGSERIAL PRIMARY KEY,
  first_name      VARCHAR(50) NOT NULL,
  last_name       VARCHAR(50) NOT NULL,
  middle_name     VARCHAR(50),
  user_contacts   JSONB NOT NULL DEFAULT '{}'::jsonb,
  login           CITEXT UNIQUE NOT NULL,
  password_hash   VARCHAR(255) NOT NULL,              -- хватает под Django PBKDF2/argon2
  role            VARCHAR(20)  NOT NULL CHECK (role IN ('STUDENT','PROFESSOR','ADMIN')),
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  archived_at     TIMESTAMPTZ,
  is_archived     BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS students (
  student_id   BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
  group_number VARCHAR(16) NOT NULL,
  faculty      VARCHAR(50) NOT NULL,
  archived_at  TIMESTAMPTZ,
  is_archived  BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS professors (
  professor_id BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
  department   VARCHAR(50) NOT NULL,
  faculty      VARCHAR(50) NOT NULL,
  archived_at  TIMESTAMPTZ,
  is_archived  BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS admins (
  admin_id    BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE
  -- архивация админов обычно делается через users.archived_at
);

-- ADMIN LOGS
CREATE TABLE IF NOT EXISTS admin_logs (
  admin_log_id    BIGSERIAL PRIMARY KEY,
  admin_id        BIGINT REFERENCES admins(admin_id) ON DELETE SET NULL,
  admin_action    VARCHAR(100) NOT NULL,
  log_created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  actor_user_id   BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
  details         JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- APPLICATIONS
CREATE TABLE IF NOT EXISTS application_details (
  ap_info_id               BIGSERIAL PRIMARY KEY,
  how_discovered           TEXT,
  name                     VARCHAR(100),
  specialization           VARCHAR(50),
  priority_direction       VARCHAR(50),
  time_to_realise          VARCHAR(100),
  actuality                TEXT,
  problem                  TEXT,
  goal                     TEXT,
  main_tasks               TEXT,
  product_result           TEXT,
  tech_level_preparation   TEXT,
  budget                   TEXT,
  who_finance              TEXT,
  education_resources      TEXT,
  infrastructure_acceptance TEXT,
  archived_at              TIMESTAMPTZ,
  is_archived              BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS project_applications (
  application_id BIGSERIAL PRIMARY KEY,
  user_id        BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  ap_info_id     BIGINT NOT NULL UNIQUE REFERENCES application_details(ap_info_id) ON DELETE CASCADE,
  status         application_status NOT NULL DEFAULT 'pending',
  act_at         TIMESTAMPTZ,
  archived_at    TIMESTAMPTZ,
  is_archived    BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

-- PROJECTS AND MEMBERS
CREATE TABLE IF NOT EXISTS projects (
  project_id          BIGSERIAL PRIMARY KEY,
  project_name        VARCHAR(150) NOT NULL,
  project_description TEXT,
  project_status      project_status NOT NULL DEFAULT 'active',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  release_date        TIMESTAMPTZ,
  application_id      BIGINT UNIQUE REFERENCES project_applications(application_id) ON DELETE SET NULL,
  specialization      VARCHAR(50),
  archived_at         TIMESTAMPTZ,
  is_archived         BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS project_members (
  id             BIGSERIAL PRIMARY KEY,
  project_id     BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  member_student BIGINT REFERENCES students(student_id)   ON DELETE CASCADE,
  member_prof    BIGINT REFERENCES professors(professor_id) ON DELETE CASCADE,
  role_in_team   VARCHAR(100),
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at        TIMESTAMPTZ,
  archived_at    TIMESTAMPTZ,
  is_archived    BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED,
  CONSTRAINT project_member_one_kind_check
    CHECK ((member_student IS NOT NULL) <> (member_prof IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS unique_index_project_member_student
  ON project_members(project_id, member_student)
  WHERE member_student IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS unique_index_project_member_prof
  ON project_members(project_id, member_prof)
  WHERE member_prof IS NOT NULL;

-- TASKS & REPORTS
CREATE TABLE IF NOT EXISTS tasks (
  task_id          BIGSERIAL PRIMARY KEY,
  project_id       BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  task_name        VARCHAR(100) NOT NULL,
  task_description TEXT,
  executor_student BIGINT REFERENCES students(student_id) ON DELETE SET NULL,
  task_status      task_status NOT NULL DEFAULT 'open',
  task_deadline    TIMESTAMPTZ,
  archived_at      TIMESTAMPTZ,
  is_archived      BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED
);

CREATE TABLE IF NOT EXISTS reports (
  report_id        BIGSERIAL PRIMARY KEY,
  task_id          BIGINT NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
  student_id       BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
  file_path        VARCHAR(512),
  external_url     VARCHAR(2048),
  status           report_status NOT NULL DEFAULT 'submitted',
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by_prof BIGINT REFERENCES professors(professor_id) ON DELETE SET NULL,
  reviewed_at      TIMESTAMPTZ,
  review_comment   TEXT,
  archived_at      TIMESTAMPTZ,
  is_archived      BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED,
  CONSTRAINT reports_file_or_url_chk
    CHECK ( (file_path IS NOT NULL) <> (external_url IS NOT NULL) ),
  CONSTRAINT reports_needs_fix_comment_chk
    CHECK (status <> 'needs_fix' OR review_comment IS NOT NULL)
);

-- PROJECT SCHEDULE
CREATE TABLE IF NOT EXISTS project_schedule (
  schedule_id BIGSERIAL PRIMARY KEY,
  project_id  BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  title       VARCHAR(200) NOT NULL,
  description TEXT,
  starts_at   TIMESTAMPTZ NOT NULL,
  ends_at     TIMESTAMPTZ NOT NULL,
  location    VARCHAR(200),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at TIMESTAMPTZ,
  is_archived BOOLEAN GENERATED ALWAYS AS (archived_at IS NOT NULL) STORED,
  CONSTRAINT project_schedule_time_chk CHECK (ends_at > starts_at)
);

-- ИНДЕКСЫ
CREATE INDEX IF NOT EXISTS idx_tasks_project          ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_reports_task           ON reports(task_id);
CREATE INDEX IF NOT EXISTS idx_reports_student        ON reports(student_id);
CREATE INDEX IF NOT EXISTS idx_projects_status        ON projects(project_status);
CREATE INDEX IF NOT EXISTS idx_project_schedule_proj   ON project_schedule(project_id);
CREATE INDEX IF NOT EXISTS idx_project_schedule_start  ON project_schedule(starts_at);

-- Логи
CREATE INDEX IF NOT EXISTS idx_admin_logs_action   ON admin_logs (admin_action);
CREATE INDEX IF NOT EXISTS idx_admin_logs_created  ON admin_logs (log_created_at);
CREATE INDEX IF NOT EXISTS idx_admin_logs_details  ON admin_logs USING GIN (details);
