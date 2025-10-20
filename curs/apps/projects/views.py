from django.views.generic import TemplateView


class MyProjectsView(TemplateView):
    template_name = "projects/my_projects.html"
