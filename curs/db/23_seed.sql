BEGIN;

-- =========================
-- USERS (логины уникальны, CITEXT)
-- =========================
INSERT INTO users (first_name,last_name,middle_name,user_contacts,login,password_hash,role)
VALUES
  ('Иван','Иванов',NULL,'{"phone":"+7-900-111-11-11"}','student1','pbkdf2:demo', 'STUDENT'),
  ('Мария','Петрова',NULL,'{"telegram":"@masha"}','student2','pbkdf2:demo', 'STUDENT'),
  ('Павел','Сергеев',NULL,'{}','prof1','pbkdf2:demo', 'PROFESSOR'),
  ('Елена','Кузнецова',NULL,'{}','prof2','pbkdf2:demo', 'PROFESSOR'),
  ('Админ','Системный',NULL,'{}','admin','pbkdf2:demo', 'ADMIN');

-- =========================
-- ROLE PROFILES (student/professor/admin связываются по login → user_id)
-- =========================
INSERT INTO students (user_id, group_number, faculty)
SELECT u.user_id, 'IU6-31', 'ФОПФ' FROM users u WHERE u.login='student1';
INSERT INTO students (user_id, group_number, faculty)
SELECT u.user_id, 'IU6-32', 'ФИВТ' FROM users u WHERE u.login='student2';

INSERT INTO professors (user_id, department, faculty)
SELECT u.user_id, 'Кафедра ИУ6', 'МГТУ' FROM users u WHERE u.login='prof1';
INSERT INTO professors (user_id, department, faculty)
SELECT u.user_id, 'Кафедра ИУ5', 'МГТУ' FROM users u WHERE u.login='prof2';

INSERT INTO admins (user_id)
SELECT u.user_id FROM users u WHERE u.login='admin';

-- =========================
-- APPLICATION DETAILS (карточки заявок)
-- =========================
INSERT INTO application_details
(how_discovered,name,specialization,priority_direction,time_to_realise,actuality,problem,goal,main_tasks,product_result,tech_level_preparation,budget,who_finance,education_resources,infrastructure_acceptance)
VALUES
 ('Хакатон','Система мониторинга качества воздуха','IoT','Экология','2 семестра',
  'Смог в городе','Нет локальных датчиков','Собрать сеть сенсоров',
  'Развертывание сенсоров; Сбор данных','Дашборд + API','Прототип','0.5 млн','Фонд','Лабы вуза','Готова'),
 ('Конференция','Платформа проверки отчётов','Software','Образование','1 семестр',
  'Много ручной проверки','Неунифицированные отчёты','Автопроверки и трекинг статусов',
  'Интеграция; Метрики','Веб-сервис','Готовность 30%','0.2 млн','Кафедра','Компьютерный класс','Нужен сервер');

-- =========================
-- PROJECT APPLICATIONS (заявки пользователей)
-- =========================
INSERT INTO project_applications (user_id, ap_info_id, status, act_at)
SELECT u.user_id, ad.ap_info_id, 'approved', now()
FROM users u JOIN application_details ad ON ad.name='Система мониторинга качества воздуха'
WHERE u.login='student1';

INSERT INTO project_applications (user_id, ap_info_id, status, act_at)
SELECT u.user_id, ad.ap_info_id, 'approved', now()
FROM users u JOIN application_details ad ON ad.name='Платформа проверки отчётов'
WHERE u.login='student2';

-- =========================
-- PROJECTS (2 проекта из утверждённых заявок)
-- =========================
INSERT INTO projects (project_name, project_description, project_status, application_id, specialization, created_at)
SELECT
  'AirSense', 'Сенсоры качества воздуха + дашборд', 'active',
  pa.application_id, 'IoT', now()
FROM project_applications pa
JOIN application_details ad ON ad.ap_info_id=pa.ap_info_id
WHERE ad.name='Система мониторинга качества воздуха'
ON CONFLICT DO NOTHING;

INSERT INTO projects (project_name, project_description, project_status, application_id, specialization, created_at)
SELECT
  'ReportCheck', 'Автоматизация проверки студенческих отчётов', 'active',
  pa.application_id, 'Software', now()
FROM project_applications pa
JOIN application_details ad ON ad.ap_info_id=pa.ap_info_id
WHERE ad.name='Платформа проверки отчётов'
ON CONFLICT DO NOTHING;

-- =========================
-- PROJECT MEMBERS (студенты + преподаватели)
-- =========================
-- AirSense: student1 + prof1
INSERT INTO project_members (project_id, member_student, role_in_team, joined_at)
SELECT p.project_id, s.student_id, 'Разработчик', now()
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='AirSense';

INSERT INTO project_members (project_id, member_prof, role_in_team, joined_at)
SELECT p.project_id, pr.professor_id, 'Научрук', now()
FROM projects p
JOIN professors pr ON pr.user_id = (SELECT user_id FROM users WHERE login='prof1')
WHERE p.project_name='AirSense';

-- ReportCheck: student2 + prof2
INSERT INTO project_members (project_id, member_student, role_in_team, joined_at)
SELECT p.project_id, s.student_id, 'Аналитик', now()
FROM projects p
JOIN students s ON s.user_id = (SELECT user_id FROM users WHERE login='student2')
WHERE p.project_name='ReportCheck';

INSERT INTO project_members (project_id, member_prof, role_in_team, joined_at)
SELECT p.project_id, pr.professor_id, 'Куратор', now()
FROM projects p
JOIN professors pr ON pr.user_id = (SELECT user_id FROM users WHERE login='prof2')
WHERE p.project_name='ReportCheck';

-- =========================
-- TASKS (по 2 штуки на проект, один с исполнителем)
-- =========================
-- AirSense
INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Сбор датчиков', 'Закупка и настройка 10 сенсоров',
       s.student_id, 'open', now() + interval '30 days'
FROM projects p
LEFT JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student1')
WHERE p.project_name='AirSense';

INSERT INTO tasks (project_id, task_name, task_description, task_status, task_deadline)
SELECT p.project_id, 'Дизайн дашборда', 'Макеты экранов и навигации',
       'open', now() + interval '45 days'
FROM projects p
WHERE p.project_name='AirSense';

-- ReportCheck
INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline)
SELECT p.project_id, 'Импорт шаблонов', 'Загрузить шаблоны проверок и правила',
       s.student_id, 'open', now() + interval '20 days'
FROM projects p
LEFT JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student2')
WHERE p.project_name='ReportCheck';

INSERT INTO tasks (project_id, task_name, task_description, task_status, task_deadline)
SELECT p.project_id, 'Метрики качества', 'Определить KPI автопроверок',
       'open', now() + interval '35 days'
FROM projects p
WHERE p.project_name='ReportCheck';

-- =========================
-- REPORTS (каждому проекту по 2 отчёта с разными статусами)
--  - для CHECK: либо file_path, либо external_url
--  - submitted: без reviewed_*
--  - approved/needs_fix: с reviewed_*; needs_fix требует комментарий
-- =========================
-- AirSense: по задаче "Сбор датчиков"
INSERT INTO reports (task_id, student_id, external_url, status, submitted_at)
SELECT t.task_id, s.student_id, 'https://example.com/airsense/plan', 'submitted', now()
FROM tasks t
JOIN projects p ON p.project_id=t.project_id AND p.project_name='AirSense'
JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student1')
WHERE t.task_name='Сбор датчиков';

INSERT INTO reports (task_id, student_id, file_path, status, submitted_at, reviewed_by_prof, reviewed_at, review_comment)
SELECT t.task_id, s.student_id, '/uploads/airsense/photo1.png', 'approved', now() - interval '1 day',
       pr.professor_id, now(), 'Ок'
FROM tasks t
JOIN projects p ON p.project_id=t.project_id AND p.project_name='AirSense'
JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student1')
JOIN professors pr ON pr.user_id=(SELECT user_id FROM users WHERE login='prof1')
WHERE t.task_name='Сбор датчиков';

-- ReportCheck: по задаче "Импорт шаблонов"
INSERT INTO reports (task_id, student_id, external_url, status, submitted_at)
SELECT t.task_id, s.student_id, 'https://example.com/reportcheck/readme', 'submitted', now()
FROM tasks t
JOIN projects p ON p.project_id=t.project_id AND p.project_name='ReportCheck'
JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student2')
WHERE t.task_name='Импорт шаблонов';

INSERT INTO reports (task_id, student_id, file_path, status, submitted_at, reviewed_by_prof, reviewed_at, review_comment)
SELECT t.task_id, s.student_id, '/uploads/reportcheck/run1.pdf', 'needs_fix', now() - interval '2 days',
       pr.professor_id, now(), 'Исправить формат ссылок'
FROM tasks t
JOIN projects p ON p.project_id=t.project_id AND p.project_name='ReportCheck'
JOIN students s ON s.user_id=(SELECT user_id FROM users WHERE login='student2')
JOIN professors pr ON pr.user_id=(SELECT user_id FROM users WHERE login='prof2')
WHERE t.task_name='Импорт шаблонов';

-- =========================
-- PROJECT SCHEDULE (по событию на проект)
-- =========================
INSERT INTO project_schedule (project_id, title, description, starts_at, ends_at, location)
SELECT p.project_id, 'Статус-встреча', 'Обсуждение рисков', now() + interval '7 days',
       now() + interval '7 days' + interval '1 hour', 'ауд. 101'
FROM projects p WHERE p.project_name='AirSense';

INSERT INTO project_schedule (project_id, title, description, starts_at, ends_at, location)
SELECT p.project_id, 'Демо спринта', 'Промежуточные результаты', now() + interval '10 days',
       now() + interval '10 days' + interval '2 hours', 'ауд. 202'
FROM projects p WHERE p.project_name='ReportCheck';

-- =========================
-- ADMIN LOGS (2 записи)
-- =========================
INSERT INTO admin_logs (admin_id, admin_action, log_created_at, actor_user_id, details)
SELECT a.admin_id, 'create_project', now(), u.user_id, '{"project":"AirSense"}'::jsonb
FROM admins a
JOIN users u ON u.login='admin'
LIMIT 1;

INSERT INTO admin_logs (admin_id, admin_action, log_created_at, actor_user_id, details)
SELECT a.admin_id, 'add_member', now(), u.user_id, '{"project":"ReportCheck","member":"student2"}'::jsonb
FROM admins a
JOIN users u ON u.login='admin'
LIMIT 1;

COMMIT;
