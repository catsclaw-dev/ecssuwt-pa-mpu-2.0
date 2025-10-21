from django.urls import path
from .views import AdminDashboardView


app_name = "adminboard"
urlpatterns = [
    path("", AdminDashboardView.as_view(), name="index"),
]
