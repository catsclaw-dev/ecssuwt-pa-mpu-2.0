ALTER TABLE admin_logs
  ADD COLUMN IF NOT EXISTS actor_user_id BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS details JSONB DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS ix_admin_logs_action   ON admin_logs (admin_action);
CREATE INDEX IF NOT EXISTS ix_admin_logs_created  ON admin_logs (log_created_at);
CREATE INDEX IF NOT EXISTS ix_admin_logs_details  ON admin_logs USING GIN (details);
