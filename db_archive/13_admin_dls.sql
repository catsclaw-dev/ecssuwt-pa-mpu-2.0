BEGIN;
GRANT USAGE ON SCHEMA public TO role_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  users, admins, students, professors,
  projects, project_members,
  tasks, reports,
  application_details, project_applications
TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_admin;
COMMIT;
