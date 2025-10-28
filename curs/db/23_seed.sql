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


INSERT INTO users (login, role, first_name, middle_name, last_name, password_hash, user_contacts)
VALUES
('seed_admin01','ADMIN','Анна','Ивановна','Кузнецова','<<HASH>>','{"email":"admin01@example.com","phone":"+7 900 111-11-11","telegram":"@admin01"}'::jsonb),
('seed_admin02','ADMIN','Иван','Сергеевич','Морозов','<<HASH>>','{"email":"admin02@example.com","phone":"+7 900 111-22-22","telegram":"@admin02"}'::jsonb),
('seed_admin03','ADMIN','Павел','Алексеевич','Соколов','<<HASH>>','{"email":"admin03@example.com","phone":"+7 900 111-33-33","telegram":"@admin03"}'::jsonb);

INSERT INTO admins (user_id)
SELECT user_id FROM users WHERE login IN ('seed_admin01','seed_admin02','seed_admin03');

INSERT INTO users (login, role, first_name, middle_name, last_name, password_hash, user_contacts)
VALUES
('seed_prof01','PROFESSOR','Мария','Дмитриевна','Иванова','<<HASH>>','{"email":"prof01@example.com","phone":"+7 900 200-01-01","telegram":"@prof01"}'::jsonb),
('seed_prof02','PROFESSOR','Дмитрий','Сергеевич','Кузнецов','<<HASH>>','{"email":"prof02@example.com","phone":"+7 900 200-02-02","telegram":"@prof02"}'::jsonb),
('seed_prof03','PROFESSOR','Екатерина','Михайловна','Петрова','<<HASH>>','{"email":"prof03@example.com","phone":"+7 900 200-03-03","telegram":"@prof03"}'::jsonb),
('seed_prof04','PROFESSOR','Сергей','Иванович','Лебедев','<<HASH>>','{"email":"prof04@example.com","phone":"+7 900 200-04-04","telegram":"@prof04"}'::jsonb),
('seed_prof05','PROFESSOR','Ольга','Алексеевна','Соколова','<<HASH>>','{"email":"prof05@example.com","phone":"+7 900 200-05-05","telegram":"@prof05"}'::jsonb);

INSERT INTO professors (user_id, department, faculty) VALUES
((SELECT user_id FROM users WHERE login='seed_prof01'),'Кибернетика','ФКН'),
((SELECT user_id FROM users WHERE login='seed_prof02'),'ПОИТ','ФИТ'),
((SELECT user_id FROM users WHERE login='seed_prof03'),'Прикладная математика','ФПМИ'),
((SELECT user_id FROM users WHERE login='seed_prof04'),'ИСиТ','ФИТ'),
((SELECT user_id FROM users WHERE login='seed_prof05'),'КСиС','ФКТИ');

INSERT INTO users (login, role, first_name, middle_name, last_name, password_hash, user_contacts)
VALUES
('seed_stud01','STUDENT','Алексей','Павлович','Сидоров','<<HASH>>','{"email":"stud01@example.com","phone":"+7 900 300-01-01","telegram":"@stud01"}'::jsonb),
('seed_stud02','STUDENT','Полина','Ивановна','Егорова','<<HASH>>','{"email":"stud02@example.com","phone":"+7 900 300-02-02","telegram":"@stud02"}'::jsonb),
('seed_stud03','STUDENT','Никита','Андреевич','Ковалёв','<<HASH>>','{"email":"stud03@example.com","phone":"+7 900 300-03-03","telegram":"@stud03"}'::jsonb),
('seed_stud04','STUDENT','Анна','Сергеевна','Тихонова','<<HASH>>','{"email":"stud04@example.com","phone":"+7 900 300-04-04","telegram":"@stud04"}'::jsonb),
('seed_stud05','STUDENT','Илья','Денисович','Смирнов','<<HASH>>','{"email":"stud05@example.com","phone":"+7 900 300-05-05","telegram":"@stud05"}'::jsonb),
('seed_stud06','STUDENT','Дарья','Петровна','Киселёва','<<HASH>>','{"email":"stud06@example.com","phone":"+7 900 300-06-06","telegram":"@stud06"}'::jsonb),
('seed_stud07','STUDENT','Михаил','Егорович','Комаров','<<HASH>>','{"email":"stud07@example.com","phone":"+7 900 300-07-07","telegram":"@stud07"}'::jsonb),
('seed_stud08','STUDENT','Елизавета','Алексеевна','Громова','<<HASH>>','{"email":"stud08@example.com","phone":"+7 900 300-08-08","telegram":"@stud08"}'::jsonb),
('seed_stud09','STUDENT','Кирилл','Михайлович','Волков','<<HASH>>','{"email":"stud09@example.com","phone":"+7 900 300-09-09","telegram":"@stud09"}'::jsonb),
('seed_stud10','STUDENT','Софья','Ильинична','Борисова','<<HASH>>','{"email":"stud10@example.com","phone":"+7 900 300-10-10","telegram":"@stud10"}'::jsonb),
('seed_stud11','STUDENT','Пётр','Сергеевич','Зайцев','<<HASH>>','{"email":"stud11@example.com","phone":"+7 900 300-11-11","telegram":"@stud11"}'::jsonb),
('seed_stud12','STUDENT','Юлия','Андреевна','Семенова','<<HASH>>','{"email":"stud12@example.com","phone":"+7 900 300-12-12","telegram":"@stud12"}'::jsonb),
('seed_stud13','STUDENT','Владимир','Игоревич','Алексеев','<<HASH>>','{"email":"stud13@example.com","phone":"+7 900 300-13-13","telegram":"@stud13"}'::jsonb),
('seed_stud14','STUDENT','Алёна','Павловна','Кузьмина','<<HASH>>','{"email":"stud14@example.com","phone":"+7 900 300-14-14","telegram":"@stud14"}'::jsonb),
('seed_stud15','STUDENT','Егор','Олегович','Мельников','<<HASH>>','{"email":"stud15@example.com","phone":"+7 900 300-15-15","telegram":"@stud15"}'::jsonb);

INSERT INTO students (user_id, group_number, faculty) VALUES
((SELECT user_id FROM users WHERE login='seed_stud01'),'B01-24','ФКН'),
((SELECT user_id FROM users WHERE login='seed_stud02'),'B01-24','ФКН'),
((SELECT user_id FROM users WHERE login='seed_stud03'),'B02-24','ФПМИ'),
((SELECT user_id FROM users WHERE login='seed_stud04'),'B02-24','ФПМИ'),
((SELECT user_id FROM users WHERE login='seed_stud05'),'B03-24','ФИТ'),
((SELECT user_id FROM users WHERE login='seed_stud06'),'B03-24','ФИТ'),
((SELECT user_id FROM users WHERE login='seed_stud07'),'B04-24','ФКТИ'),
((SELECT user_id FROM users WHERE login='seed_stud08'),'B04-24','ФКТИ'),
((SELECT user_id FROM users WHERE login='seed_stud09'),'B05-24','ФУП'),
((SELECT user_id FROM users WHERE login='seed_stud10'),'B05-24','ФУП'),
((SELECT user_id FROM users WHERE login='seed_stud11'),'B06-24','ФММ'),
((SELECT user_id FROM users WHERE login='seed_stud12'),'B06-24','ФММ'),
((SELECT user_id FROM users WHERE login='seed_stud13'),'B07-24','ФЭФ'),
((SELECT user_id FROM users WHERE login='seed_stud14'),'B07-24','ФЭФ'),
((SELECT user_id FROM users WHERE login='seed_stud15'),'B08-24','ФИТ');

INSERT INTO projects (project_name, project_description, project_status, release_date, specialization, created_at, archived_at) VALUES
('Проект Альфа','Учебный проект по Web.','active',  now() + interval '30 days','Web',  now() - interval '20 days', NULL),
('Проект Браво','Мобильное приложение.','paused',  now() + interval '45 days','Mobile',now() - interval '40 days', NULL),
('Проект Чарли','ML/Computer Vision.','active',   now() + interval '10 days','ML',   now() - interval '10 days', NULL),
('Проект Дельта','IoT прототип.','active',        now() + interval '60 days','IoT',  now() - interval '50 days', NULL),
('Проект Эхо','GameDev учебный проект.','active', now() + interval '15 days','GameDev', now() - interval '25 days', NULL),
('Проект Фокстрот','Data Engineering.','archived',now() - interval '30 days','DataEng',now() - interval '120 days', now() - interval '25 days'),
('Проект Гольф','DevOps практикум.','active',     now() + interval '90 days','DevOps', now() - interval '5 days', NULL),
('Проект Хотел','AR/VR демо.','archived',         now() - interval '5 days','AR/VR',  now() - interval '80 days', now() - interval '3 days');

INSERT INTO project_members (project_id, member_prof, role_in_team, joined_at) VALUES
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),   (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof01'), 'наставник', now() - interval '18 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),   (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof02'), 'наставник', now() - interval '35 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Чарли'),   (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof03'), 'наставник', now() - interval '9 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Дельта'),  (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof04'), 'наставник', now() - interval '48 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Эхо'),     (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof05'), 'наставник', now() - interval '22 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Гольф'),   (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof01'), 'наставник', now() - interval '4 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Хотел'),   (SELECT professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof02'), 'наставник', now() - interval '70 days');

INSERT INTO project_members (project_id, member_student, role_in_team, joined_at) VALUES
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud01'),'frontend', now() - interval '17 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud02'),'backend',  now() - interval '17 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud03'),'pm',       now() - interval '16 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud04'),'ios',      now() - interval '34 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud05'),'android',  now() - interval '34 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud06'),'qa',       now() - interval '32 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Чарли'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud07'),'cv',       now() - interval '8 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Чарли'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud08'),'ml',       now() - interval '8 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Дельта'), (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud09'),'hw',       now() - interval '47 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Дельта'), (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud10'),'fw',       now() - interval '47 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Эхо'),    (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud11'),'gamedesign', now() - interval '21 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Эхо'),    (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud12'),'unity',   now() - interval '20 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Гольф'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud13'),'devops',  now() - interval '3 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Хотел'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud14'),'3d',      now() - interval '69 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Хотел'),  (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud15'),'ue',      now() - interval '69 days');

INSERT INTO tasks (project_id, task_name, task_description, executor_student, task_status, task_deadline) VALUES
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),'Верстка лендинга','Собрать макет Figma.',(SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud01'),'open',      now() + interval '14 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),'API авторизация','JWT/refresh, документация.',(SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud02'),'in_review', now() + interval '10 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Альфа'),'Спринт планирование','Созвон с наставником.',NULL,'done', now() - interval '1 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),'Экран логина iOS','UIKit/SwiftUI', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud04'),'open', now() + interval '12 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Браво'),'Экран логина Android','Compose', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud05'),'open', now() + interval '12 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Чарли'),'Датасет','Собрать 1k изображений.', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud07'),'open', now() + interval '20 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Чарли'),'Бейзлайн','ResNet34 baseline.', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud08'),'in_review', now() + interval '18 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Дельта'),'Плата v1','Схема + разводка.', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud09'),'open', now() + interval '30 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Эхо'),'Прототип геймплея','Core loop', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud11'),'open', now() + interval '16 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Гольф'),'CI/CD пайплайн','GitHub Actions', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud13'),'done', now() - interval '10 days'),
((SELECT project_id FROM projects WHERE project_name='Проект Хотел'),'Сцена в UE','VR-демо', (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud15'),'open', now() + interval '40 days');

INSERT INTO reports (task_id, student_id, external_url, file_path, status, submitted_at)
VALUES
((SELECT t.task_id FROM tasks t JOIN projects p ON p.project_id=t.project_id WHERE p.project_name='Проект Альфа'  AND t.task_name='Верстка лендинга'),
 (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud01'),
 'https://example.com/report/a1', NULL, 'submitted', now() - interval '1 days'
),
((SELECT t.task_id FROM tasks t JOIN projects p ON p.project_id=t.project_id WHERE p.project_name='Проект Чарли' AND t.task_name='Бейзлайн'),
 (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud08'),
 'https://example.com/report/c1', NULL, 'submitted', now() - interval '2 days'
);

INSERT INTO reports (task_id, student_id, external_url, file_path, status, submitted_at, reviewed_at, reviewed_by_prof)
VALUES
((SELECT t.task_id FROM tasks t JOIN projects p ON p.project_id=t.project_id WHERE p.project_name='Проект Гольф' AND t.task_name='CI/CD пайплайн'),
 (SELECT s.student_id FROM students s JOIN users u ON u.user_id=s.user_id WHERE u.login='seed_stud13'),
 'https://example.com/report/g1', NULL, 'approved', now() - interval '12 days', now() - interval '10 days',
 (SELECT p.professor_id FROM professors p JOIN users u ON u.user_id=p.user_id WHERE u.login='seed_prof01')
);
