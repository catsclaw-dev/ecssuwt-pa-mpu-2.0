from django.views.generic import TemplateView


class AnalyticsHome(TemplateView):
    template_name = "analytics/home.html"
