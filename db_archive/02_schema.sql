CREATE TABLE IF NOT EXISTS users (
  user_id       BIGSERIAL PRIMARY KEY,
  first_name    TEXT NOT NULL,
  last_name     TEXT NOT NULL,
  middle_name   TEXT,
  user_contacts JSONB DEFAULT '{}'::jsonb,
  login         CITEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('STUDENT','PROFESSOR','ADMIN')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS students (
  student_id BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  group_number TEXT NOT NULL,
  faculty      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS professors (
  professor_id BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  department   TEXT NOT NULL,
  faculty      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS admins (
  admin_id BIGSERIAL PRIMARY KEY,
  user_id  BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS admin_logs (
  admin_log_id   BIGSERIAL PRIMARY KEY,
  admin_id       BIGINT REFERENCES admins(admin_id) ON DELETE SET NULL,
  admin_action   TEXT NOT NULL,
  log_created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS application_details (
  ap_info_id BIGSERIAL PRIMARY KEY,
  how_discovered TEXT,
  name TEXT,
  specialization TEXT,
  priority_direction TEXT,
  time_to_realise TEXT,
  actuality TEXT,
  problem TEXT,
  goal TEXT,
  main_tasks TEXT,
  product_result TEXT,
  tech_level_preparation TEXT,
  budget TEXT,
  who_finance TEXT,
  education_resources TEXT,
  infrastructure_acceptance TEXT
);

CREATE TABLE IF NOT EXISTS project_applications (
  application_id BIGSERIAL PRIMARY KEY,
  user_id        BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  ap_info_id     BIGINT NOT NULL REFERENCES application_details(ap_info_id) ON DELETE CASCADE,
  status         application_status NOT NULL DEFAULT 'pending',
  act_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS projects (
  project_id          BIGSERIAL PRIMARY KEY,
  project_name        TEXT NOT NULL,
  project_description TEXT,
  project_status      project_status NOT NULL DEFAULT 'active',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  release_date        TIMESTAMPTZ,
  application_id      BIGINT UNIQUE REFERENCES project_applications(application_id) ON DELETE SET NULL,
  specialization      TEXT
);

CREATE TABLE IF NOT EXISTS project_members (
  id             BIGSERIAL PRIMARY KEY,
  project_id     BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  member_student BIGINT REFERENCES students(student_id) ON DELETE CASCADE,
  member_prof    BIGINT REFERENCES professors(professor_id) ON DELETE CASCADE,
  role_in_team   TEXT,
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at        TIMESTAMPTZ,
  CONSTRAINT project_member_one_kind_chk
    CHECK ((member_student IS NOT NULL) <> (member_prof IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS tasks (
  task_id          BIGSERIAL PRIMARY KEY,
  project_id       BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  task_name        TEXT NOT NULL,
  task_description TEXT,
  executor_student BIGINT REFERENCES students(student_id) ON DELETE SET NULL,
  task_status      task_status NOT NULL DEFAULT 'open',
  task_deadline    TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS reports (
  report_id        BIGSERIAL PRIMARY KEY,
  task_id          BIGINT NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
  student_id       BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
  file_path        TEXT,
  external_url     TEXT,
  status           report_status NOT NULL DEFAULT 'submitted',
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by_prof BIGINT REFERENCES professors(professor_id) ON DELETE SET NULL,
  reviewed_at      TIMESTAMPTZ,
  CONSTRAINT reports_file_or_url_chk
    CHECK (file_path IS NOT NULL OR external_url IS NOT NULL)
);
