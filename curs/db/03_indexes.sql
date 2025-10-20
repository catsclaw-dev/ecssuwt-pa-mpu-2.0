CREATE INDEX IF NOT EXISTS idx_tasks_project   ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_reports_task    ON reports(task_id);
CREATE INDEX IF NOT EXISTS idx_reports_student ON reports(student_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(project_status);
