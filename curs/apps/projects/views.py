from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView
from django.http import Http404
from .mixins import ProjectAccessMixin
from .repo import (
    get_student_id_by_user,
    get_professor_id_by_user,
    get_projects_for_student,
    get_projects_for_professor,
    get_projects_for_admin,
    get_project,
    get_project_members,
    get_project_progress,
    get_project_tasks_with_status,
    get_project_schedule,
)


class MyProjectsView(LoginRequiredMixin, TemplateView):
    template_name = "projects/my_projects.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user
        if user.role == "STUDENT":
            sid = get_student_id_by_user(user.user_id)
            ctx["projects"] = get_projects_for_student(sid) if sid else []
        elif user.role == "PROFESSOR":
            pid = get_professor_id_by_user(user.user_id)
            ctx["projects"] = get_projects_for_professor(pid) if pid else []
        else:  # ADMIN
            ctx["projects"] = get_projects_for_admin()
        return ctx


class ProjectDetailView(ProjectAccessMixin, LoginRequiredMixin, TemplateView):
    template_name = "projects/project_detail.html"

    def get_context_data(self, project_id: int, **kwargs):
        ctx = super().get_context_data(**kwargs)
        proj = get_project(project_id)
        if not proj:
            raise Http404("Проект не найден")
        ctx["project"] = proj
        ctx["members"] = get_project_members(project_id)
        ctx["progress"] = get_project_progress(project_id)
        ctx["tasks"] = get_project_tasks_with_status(project_id)
        ctx["schedule"] = get_project_schedule(project_id)
        return ctx
