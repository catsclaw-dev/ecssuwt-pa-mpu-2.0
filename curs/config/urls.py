"""
URL configuration for curs project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""

from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from apps.accounts.views import RootRedirect

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", RootRedirect.as_view(), name="root"),
    path("", include("apps.accounts.urls")),
    path("tasks/", include("apps.tasks.urls")),
    path("reports/", include("apps.reports.urls")),
    path("projects/", include("apps.projects.urls")),
    path(
        "analytics/",
        include(("apps.analytics.urls", "analytics"), namespace="analytics"),
    ),
    path(
        "showcase/", include(("apps.showcase.urls", "showcase"), namespace="showcase")
    ),
    path(
        "adminboard/",
        include(("apps.adminboard.urls", "adminboard"), namespace="adminboard"),
    ),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

handler403 = "config.views.error_403"
