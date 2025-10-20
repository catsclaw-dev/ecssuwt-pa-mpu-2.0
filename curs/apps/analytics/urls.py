from django.urls import path
from .views import AnalyticsHome

urlpatterns = [
    path("", AnalyticsHome.as_view(), name="analytics_home"),
]
