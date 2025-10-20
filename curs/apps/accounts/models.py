from django.db import models
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager


class UserManager(BaseUserManager):
    use_in_migrations = False

    def get_by_natural_key(self, username):
        return self.get(login__iexact=username)


class User(AbstractBaseUser):
    # ВАЖНО: отключаем last_login, т.к. колонки в БД нет
    last_login = None

    user_id = models.BigAutoField(primary_key=True)
    login = models.CharField(max_length=150, unique=True)
    password = models.CharField(max_length=128, db_column="password_hash")
    first_name = models.CharField(max_length=150)
    last_name = models.CharField(max_length=150)
    middle_name = models.CharField(max_length=150, null=True, blank=True)
    user_contacts = models.JSONField(default=dict)
    role = models.CharField(max_length=16)  # 'STUDENT' | 'PROFESSOR' | 'ADMIN'
    created_at = models.DateTimeField()

    USERNAME_FIELD = "login"
    REQUIRED_FIELDS = []

    objects = UserManager()

    class Meta:
        db_table = "users"
        managed = False

    @property
    def is_staff(self):
        return self.role == "ADMIN"

    @property
    def is_active(self):
        return True
