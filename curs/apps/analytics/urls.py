from django.urls import path
from .views import AnalyticsHome, ProjectsRankingView

app_name = "analytics"

urlpatterns = [
    path("", AnalyticsHome.as_view(), name="analytics_home"),
    path("projects/", ProjectsRankingView.as_view(), name="projects_ranking"),
]
