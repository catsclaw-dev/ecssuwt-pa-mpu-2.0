from django.urls import path
from .views import MyProjectsView

urlpatterns = [
    path("my/", MyProjectsView.as_view(), name="my_projects"),
]
