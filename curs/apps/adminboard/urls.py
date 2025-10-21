from django.urls import path
from .views import (
    AdminDashboardView,
    users_list,
    user_new,
    user_edit,
    user_delete,
    projects_list,
    project_new,
    project_edit,
    project_delete,
    tasks_list,
    task_new_admin,
    task_edit_admin,
    task_delete_admin,
)

app_name = "adminboard"
urlpatterns = [
    path("", AdminDashboardView.as_view(), name="index"),
    # Users
    path("users/", users_list, name="users-list"),
    path("users/new/", user_new, name="user-new"),
    path("users/<int:user_id>/edit/", user_edit, name="user-edit"),
    path("users/<int:user_id>/delete/", user_delete, name="user-delete"),
    # Projects
    path("projects/", projects_list, name="projects-list"),
    path("projects/new/", project_new, name="project-new"),
    path("projects/<int:project_id>/edit/", project_edit, name="project-edit"),
    path("projects/<int:project_id>/delete/", project_delete, name="project-delete"),
    # Tasks
    path("tasks/", tasks_list, name="tasks-list"),
    path("tasks/new/", task_new_admin, name="task-new"),
    path("tasks/<int:task_id>/edit/", task_edit_admin, name="task-edit"),
    path("tasks/<int:task_id>/delete/", task_delete_admin, name="task-delete"),
]
