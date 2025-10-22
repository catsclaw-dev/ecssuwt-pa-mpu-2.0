from django.urls import path
from .views import (
    MyProjectsView,
    ProjectDetailView,
    ProjectTeamView,
    task_new,
    schedule_new,
)

app_name = "projects"
urlpatterns = [
    path("my/", MyProjectsView.as_view(), name="my-projects"),
    path("<int:project_id>/", ProjectDetailView.as_view(), name="project-detail"),
    path("<int:project_id>/tasks/new/", task_new, name="task-new"),
    path("<int:project_id>/schedule/new/", schedule_new, name="schedule-new"),
    path("<int:project_id>/team/", ProjectTeamView.as_view(), name="project-team"),
]
