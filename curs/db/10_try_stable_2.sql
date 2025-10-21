BEGIN;

-- 1) USERS
-- Хэши временные — после импорта сделай changepassword (см. ниже).
INSERT INTO users (first_name,last_name,middle_name,user_contacts,login,password_hash,role,created_at) VALUES
  ('Админ','Сайт',NULL,'{}','admin','pbkdf2_sha256$260000$seed$placeholder','ADMIN', now()),
  ('Иван','Студентов',NULL,'{}','student1','pbkdf2_sha256$260000$seed$placeholder','STUDENT', now()),
  ('Мария','Студентова',NULL,'{}','student2','pbkdf2_sha256$260000$seed$placeholder','STUDENT', now()),
  ('Пётр','Преподавателев',NULL,'{}','prof1','pbkdf2_sha256$260000$seed$placeholder','PROFESSOR', now()),
  ('Анна','Руководитель',NULL,'{}','prof2','pbkdf2_sha256$260000$seed$placeholder','PROFESSOR', now())
ON CONFLICT (login) DO NOTHING;

-- 2) ROLES: admins / students / professors
INSERT INTO admins (user_id)
SELECT u.user_id FROM users u WHERE u.login='admin'
ON CONFLICT DO NOTHING;

INSERT INTO students (user_id, group_number, faculty)
SELECT u.user_id, 'CS-101', 'ФКН' FROM users u WHERE u.login='student1'
ON CONFLICT DO NOTHING;
INSERT INTO students (user_id, group_number, faculty)
SELECT u.user_id, 'CS-102', 'ФКН' FROM users u WHERE u.login='student2'
ON CONFLICT DO NOTHING;

INSERT INTO professors (user_id, department, faculty)
SELECT u.user_id, 'ИУ3', 'ФКН' FROM users u WHERE u.login='prof1'
ON CONFLICT DO NOTHING;
INSERT INTO professors (user_id, department, faculty)
SELECT u.user_id, 'ИУ5', 'ФКН' FROM users u WHERE u.login='prof2'
ON CONFLICT DO NOTHING;

-- 3) APPLICATION_DETAILS + PROJECT_APPLICATIONS
-- Заявка №1 (пойдёт в проект №1)
WITH ins AS (
  INSERT INTO application_details (how_discovered,name,specialization,priority_direction,time_to_realise,actuality,problem,goal,main_tasks,product_result,tech_level_preparation,budget,who_finance,education_resources,infrastructure_acceptance)
  VALUES ('Сайт', 'Кампусный портал', 'Web', 'Образование', '1 семестр', 'Высокая', 'Разрозненные сервисы', 'Единый портал', 'Аутентификация, проекты, отчёты', 'Рабочий портал', 'Средний', '0', '—', 'Да', 'Да')
  RETURNING ap_info_id
)
INSERT INTO project_applications (user_id, ap_info_id, status, act_at)
SELECT (SELECT user_id FROM users WHERE login='prof1'), ap_info_id, 'approved', now() FROM ins
ON CONFLICT DO NOTHING;

-- Заявка №2 (пойдёт в проект №2)
WITH ins AS (
  INSERT INTO application_details (how_discovered,name,specialization,priority_direction,time_to_realise,actuality,problem,goal,main_tasks,product_result,tech_level_preparation,budget,who_finance,education_resources,infrastructure_acceptance)
  VALUES ('Сайт', 'Система контроля задач', 'Web', 'R&D', '1 семестр', 'Средняя', 'Нет единого трекера', 'Унификация', 'Карточки задач, статусы', 'Рабочий трекер', 'Средний', '0', '—', 'Да', 'Да')
  RETURNING ap_info_id
)
INSERT INTO project_applications (user_id, ap_info_id, status, act_at)
SELECT (SELECT user_id FROM users WHERE login='prof2'), ap_info_id, 'approved', now() FROM ins
ON CONFLICT DO NOTHING;

-- 4) PROJECTS (привязаны к заявкам)
-- Проект 1
INSERT INTO projects (project_name, project_description, project_status, created_at, release_date, application_id, specialization)
SELECT
  'Кампусный портал',
  'Учебный проект на Django + PostgreSQL',
  'active',
  now(),
  now() + interval '30 days',
  pa.application_id,
  'Web'
FROM project_applications pa
JOIN application_details ad ON ad.ap_info_id = pa.ap_info_id
WHERE ad.name='Кампусный портал'
ON CONFLICT DO NOTHING;

-- Проект 2
INSERT INTO projects (project_name, project_description, project_status, created_at, release_date, application_id, specialization)
SELECT
  'Система контроля задач',
  'Трекер задач для учебных проектов',
  'active',
  now(),
  now() + interval '45 days',
  pa.application_id,
  'Web'
FROM project_applications pa
JOIN application_details ad ON ad.ap_info_id = pa.ap_info_id
WHERE ad.name='Система контроля задач'
ON CONFLICT DO NOTHING;

-- 5) PROJECT_MEMBERS (участники)
-- Для проекта 1: student1 + prof1
INSERT INTO project_members (project_id, member_student, role_in_team)
SELECT p.project_id, s.student_id, 'Исполнитель'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='Кампусный портал'
ON CONFLICT DO NOTHING;

INSERT INTO project_members (project_id, member_prof, role_in_team)
SELECT p.project_id, pr.professor_id, 'Руководитель'
FROM projects p
JOIN professors pr ON pr.user_id = (SELECT user_id FROM users WHERE login='prof1')
WHERE p.project_name='Кампусный портал'
ON CONFLICT DO NOTHING;

-- Для проекта 2: student2 + prof2
INSERT INTO project_members (project_id, member_student, role_in_team)
SELECT p.project_id, s.student_id, 'Исполнитель'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student2')
WHERE p.project_name='Система контроля задач'
ON CONFLICT DO NOTHING;

INSERT INTO project_members (project_id, member_prof, role_in_team)
SELECT p.project_id, pr.professor_id, 'Руководитель'
FROM projects p
JOIN professors pr ON pr.user_id = (SELECT user_id FROM users WHERE login='prof2')
WHERE p.project_name='Система контроля задач'
ON CONFLICT DO NOTHING;

-- 6) TASKS (по проектам)
-- Проект 1: три задачи
INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Первый отчёт', 'Подготовить вводный документ', s.student_id, 'done', now() + interval '7 days'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='Кампусный портал'
ON CONFLICT DO NOTHING;

INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Прототип страницы', 'Сверстать страницу проекта', s.student_id, 'in_review', now() + interval '14 days'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='Кампусный портал'
ON CONFLICT DO NOTHING;

INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'API для отчётов', 'Сделать аплоад и отображение', s.student_id, 'open', now() + interval '21 days'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='Кампусный портал'
ON CONFLICT DO NOTHING;

-- Проект 2: две задачи
INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Схема БД', 'Нормализовать таблицы', s.student_id, 'done', now() + interval '10 days'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student2')
WHERE p.project_name='Система контроля задач'
ON CONFLICT DO NOTHING;

INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Карточки задач', 'Статусы и фильтры', s.student_id, 'open', now() + interval '20 days'
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student2')
WHERE p.project_name='Система контроля задач'
ON CONFLICT DO NOTHING;

-- 7) REPORTS (история по задачам) + статусы
-- Для проекта 1:
-- a) по задаче 'Первый отчёт' — есть submitted и approved
WITH t AS (
  SELECT t.task_id, p.project_id
  FROM tasks t JOIN projects p ON p.project_id=t.project_id
  WHERE p.project_name='Кампусный портал' AND t.task_name='Первый отчёт'
),
st AS (
  SELECT student_id FROM students WHERE user_id=(SELECT user_id FROM users WHERE login='student1')
),
pr AS (
  SELECT professor_id FROM professors WHERE user_id=(SELECT user_id FROM users WHERE login='prof1')
)
INSERT INTO reports (task_id, student_id, file_path, external_url, status, submitted_at, reviewed_by_prof, reviewed_at)
SELECT t.task_id, (SELECT student_id FROM st), NULL, 'https://example.com/report_intro.pdf',
       'approved', now() - interval '1 day', (SELECT professor_id FROM pr), now() - interval '12 hours'
FROM t
ON CONFLICT DO NOTHING;

-- b) по задаче 'Прототип страницы' — только submitted (в ревью)
WITH t AS (
  SELECT t.task_id FROM tasks t
  JOIN projects p ON p.project_id=t.project_id
  WHERE p.project_name='Кампусный портал' AND t.task_name='Прототип страницы'
),
st AS (
  SELECT student_id FROM students WHERE user_id=(SELECT user_id FROM users WHERE login='student1')
)
INSERT INTO reports (task_id, student_id, file_path, external_url, status, submitted_at)
SELECT t.task_id, (SELECT student_id FROM st), NULL, 'https://example.com/prototype.png', 'submitted', now()
FROM t
ON CONFLICT DO NOTHING;

-- Для проекта 2:
-- a) по задаче 'Схема БД' — approved
WITH t AS (
  SELECT t.task_id FROM tasks t
  JOIN projects p ON p.project_id=t.project_id
  WHERE p.project_name='Система контроля задач' AND t.task_name='Схема БД'
),
st AS (
  SELECT student_id FROM students WHERE user_id=(SELECT user_id FROM users WHERE login='student2')
),
pr AS (
  SELECT professor_id FROM professors WHERE user_id=(SELECT user_id FROM users WHERE login='prof2')
)
INSERT INTO reports (task_id, student_id, file_path, external_url, status, submitted_at, reviewed_by_prof, reviewed_at)
SELECT t.task_id, (SELECT student_id FROM st), NULL, 'https://example.com/db_schema.pdf',
       'approved', now() - interval '2 days', (SELECT professor_id FROM pr), now() - interval '36 hours'
FROM t
ON CONFLICT DO NOTHING;

-- b) по задаче 'Карточки задач' — needs_fix
WITH t AS (
  SELECT t.task_id FROM tasks t
  JOIN projects p ON p.project_id=t.project_id
  WHERE p.project_name='Система контроля задач' AND t.task_name='Карточки задач'
),
st AS (
  SELECT student_id FROM students WHERE user_id=(SELECT user_id FROM users WHERE login='student2')
),
pr AS (
  SELECT professor_id FROM professors WHERE user_id=(SELECT user_id FROM users WHERE login='prof2')
)
INSERT INTO reports (task_id, student_id, file_path, external_url, status, submitted_at, reviewed_by_prof, reviewed_at)
SELECT t.task_id, (SELECT student_id FROM st), NULL, 'https://example.com/cards_draft.pdf',
       'needs_fix', now() - interval '6 hours', (SELECT professor_id FROM pr), now() - interval '3 hours'
FROM t
ON CONFLICT DO NOTHING;

-- 8) ADMIN_LOGS (минимально; если расширяли таблицу — тоже будет ок)
INSERT INTO admin_logs (admin_id, admin_action, log_created_at)
SELECT a.admin_id, 'SEED_INIT', now()
FROM admins a
JOIN users u ON u.user_id=a.user_id
WHERE u.login='admin'
ON CONFLICT DO NOTHING;

-- 9) OPTIONAL: project_schedule (если таблица существует)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='project_schedule') THEN

    -- событие расписания для проекта 1
    INSERT INTO project_schedule (project_id, title, description, starts_at, ends_at, location)
    SELECT p.project_id, 'Лекция 1', 'Вводное занятие', now() + interval '1 day', now() + interval '1 day 2 hours', 'Ауд. 101'
    FROM projects p WHERE p.project_name='Кампусный портал'
    ON CONFLICT DO NOTHING;

  END IF;
END $$;

COMMIT;

-- ПОСЛЕ сидов установи пароли (как минимум для admin/prof1/student1):
--   python manage.py changepassword admin
--   python manage.py changepassword prof1
--   python manage.py changepassword student1
