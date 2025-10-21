from django.urls import path
from .views import submit_report, moderate_task

app_name = "reports"
urlpatterns = [
    path("submit/<int:task_id>", submit_report, name="submit"),
    path("moderate/<int:task_id>", moderate_task, name="moderate"),
]
