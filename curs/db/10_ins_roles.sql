-- USERS
INSERT INTO users (first_name,last_name,login,password_hash,role)
VALUES ('Админ','Сайт','admin','superuser_ad','ADMIN')
ON CONFLICT (login) DO NOTHING;

INSERT INTO users (first_name,last_name, middle_name, login,password_hash,role)
VALUES ('Иван','Иванов', 'Иванович', 'student1','{CHANGE_ME_HASH}','STUDENT')
ON CONFLICT (login) DO NOTHING;

INSERT INTO users (first_name,last_name,login,password_hash,role)
VALUES ('Пётр','Преподавателев','prof1','{CHANGE_ME_HASH}','PROFESSOR')
ON CONFLICT (login) DO NOTHING;

-- ROLES
INSERT INTO admins (user_id)
SELECT user_id FROM users WHERE login='admin' ON CONFLICT DO NOTHING;

INSERT INTO students (user_id, group_number, faculty)
SELECT user_id, 'CS-101', 'ФКН' FROM users WHERE login='student1'
ON CONFLICT DO NOTHING;

INSERT INTO professors (user_id, department, faculty)
SELECT user_id, 'ИУ3', 'ФКН' FROM users WHERE login='prof1'
ON CONFLICT DO NOTHING;

-- PROJECTS
INSERT INTO projects (project_name, project_description, project_status, specialization, release_date)
VALUES ('Кампусный портал', 'Учебный проект по Django+PostgreSQL', 'active', 'Web', now() + interval '30 days')
RETURNING project_id;

-- Допустим, вернулся id=curr_project_id (для psql переменной):
-- В apply_sql можешь отдельными шагами сделать SELECT currval('projects_project_id_seq'), либо просто второй запрос ниже подставит последний проект.

-- MEMBERS
INSERT INTO project_members (project_id, member_student, role_in_team)
SELECT p.project_id, s.student_id, 'Исполнитель'
FROM projects p, students s
WHERE p.project_name='Кампусный портал' AND s.student_id IS NOT NULL
LIMIT 1;

INSERT INTO project_members (project_id, member_prof, role_in_team)
SELECT p.project_id, pr.professor_id, 'Руководитель'
FROM projects p, professors pr
WHERE p.project_name='Кампусный портал' AND pr.professor_id IS NOT NULL
LIMIT 1;

-- TASKS
INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_deadline)
SELECT p.project_id, 'Первый отчёт', 'Подготовить вводный документ', s.student_id, now() + interval '7 days'
FROM projects p, students s
WHERE p.project_name='Кампусный портал'
LIMIT 1;

INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_deadline)
SELECT p.project_id, 'Прототип страницы', 'Сверстать страницу проекта', s.student_id, now() + interval '14 days'
FROM projects p, students s
WHERE p.project_name='Кампусный портал'
LIMIT 1;
