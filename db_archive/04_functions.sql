CREATE OR REPLACE FUNCTION fn_auto_archive_projects() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.release_date IS NOT NULL AND NEW.release_date < now() THEN
    NEW.project_status := 'archived';
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_project_app_approve(app_id BIGINT) RETURNS BIGINT AS $$
DECLARE prj_id BIGINT;
BEGIN
  UPDATE project_applications SET status='approved', act_at=now() WHERE application_id=app_id;
  INSERT INTO projects (project_name, project_description, application_id)
  SELECT ad.name, ad.goal, app.application_id
  FROM project_applications app
  JOIN application_details ad ON ad.ap_info_id = app.ap_info_id
  WHERE app.application_id = app_id
  RETURNING project_id INTO prj_id;
  RETURN prj_id;
END; $$ LANGUAGE plpgsql;
