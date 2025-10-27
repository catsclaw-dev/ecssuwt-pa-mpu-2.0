CREATE TABLE IF NOT EXISTS project_schedule (
  schedule_id BIGSERIAL PRIMARY KEY,
  project_id  BIGINT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  description TEXT,
  starts_at   TIMESTAMPTZ NOT NULL,
  ends_at     TIMESTAMPTZ NOT NULL,
  location    TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT project_schedule_time_chk CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS ix_project_schedule_project ON project_schedule(project_id);
CREATE INDEX IF NOT EXISTS ix_project_schedule_time    ON project_schedule(starts_at);
