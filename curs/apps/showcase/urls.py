from .views import ShowcaseListView, ShowcaseDetailView
from django.urls import path

app_name = "showcase"
urlpatterns = [
    path("", ShowcaseListView.as_view(), name="list"),
    path("<int:project_id>/", ShowcaseDetailView.as_view(), name="detail"),
]
