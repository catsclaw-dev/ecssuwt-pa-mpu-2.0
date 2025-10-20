from django.urls import path
from .views import UserLoginView, logout_then_login

urlpatterns = [
    path("login/", UserLoginView.as_view(), name="login"),
    path("logout/", logout_then_login, name="logout"),
]
