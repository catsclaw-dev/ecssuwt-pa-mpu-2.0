from django.urls import path
from .views import MyProjectsView, ProjectDetailView

app_name = "projects"
urlpatterns = [
    path("my/", MyProjectsView.as_view(), name="my-projects"),
    path("<int:project_id>/", ProjectDetailView.as_view(), name="project-detail"),
]
