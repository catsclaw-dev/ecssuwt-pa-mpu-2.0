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
    project_lookup,
    project_members_admin,
    member_add,
    member_update,
    member_leave,
    user_lookup,
    user_archive,
    user_unarchive,
    project_archive,
    project_unarchive,
)

app_name = "adminboard"
urlpatterns = [
    path("", AdminDashboardView.as_view(), name="index"),
    # Users
    path("users/", users_list, name="users-list"),
    path("users/new/", user_new, name="user-new"),
    path("users/<int:user_id>/edit/", user_edit, name="user-edit"),
    path("users/<int:user_id>/delete/", user_delete, name="user-delete"),
    path("users/lookup/", user_lookup, name="users-lookup"),
    path("users/<int:user_id>/archive/", user_archive, name="user-archive"),
    path("users/<int:user_id>/unarchive/", user_unarchive, name="user-unarchive"),
    # Projects
    path("projects/<int:project_id>/archive/", project_archive, name="project-archive"),
    path(
        "projects/<int:project_id>/unarchive/",
        project_unarchive,
        name="project-unarchive",
    ),
    path("projects/", projects_list, name="projects-list"),
    path("projects/new/", project_new, name="project-new"),
    path("projects/<int:project_id>/edit/", project_edit, name="project-edit"),
    path("projects/<int:project_id>/delete/", project_delete, name="project-delete"),
    path("projects/lookup/", project_lookup, name="projects-lookup"),
    path(
        "projects/<int:project_id>/members/",
        project_members_admin,
        name="project-members-admin",
    ),
    path("projects/<int:project_id>/members/add/", member_add, name="member-add"),
    path(
        "projects/members/<int:member_id>/update/", member_update, name="member-update"
    ),
    path("projects/members/<int:member_id>/leave/", member_leave, name="member-leave"),
    # Tasks
    path("tasks/", tasks_list, name="tasks-list"),
    path("tasks/new/", task_new_admin, name="task-new"),
    path("tasks/<int:task_id>/edit/", task_edit_admin, name="task-edit"),
    path("tasks/<int:task_id>/delete/", task_delete_admin, name="task-delete"),
]
