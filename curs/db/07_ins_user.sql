-- Seed admin (password will be set via Django hasher in README)
INSERT INTO users (first_name,last_name,login,password_hash,role)
VALUES ('Admin','User','admin','', 'ADMIN')
ON CONFLICT (login) DO NOTHING;
