from django.contrib.auth.backends import BaseBackend
from django.contrib.auth.hashers import check_password
from django.db import connection


class SQLAuthBackend(BaseBackend):
    def authenticate(self, request, login=None, password=None, **kwargs):
        with connection.cursor() as cur:
            cur.execute(
                "SELECT user_id, login, password_hash, role FROM users WHERE login = %s",
                [login],
            )
            row = cur.fetchone()
            if not row:
                return None
            user_id, login, pw_hash, role = row
            if check_password(password, pw_hash):
                # вернуть прокси-пользователя (User-like объект)
                from .models import User

                return User(user_id=user_id, login=login, role=role)
        return None
