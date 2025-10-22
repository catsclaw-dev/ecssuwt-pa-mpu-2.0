BEGIN;
REVOKE INSERT, UPDATE, DELETE ON project_members FROM role_professor;
GRANT SELECT ON project_members TO role_professor;
COMMIT;
