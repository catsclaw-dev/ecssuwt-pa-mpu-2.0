from django.views.generic import RedirectView
from django.contrib.auth.views import LoginView
from django.contrib.auth import logout
from django.shortcuts import redirect


class UserLoginView(LoginView):
    template_name = "registration/login.html"


def logout_then_login(request):
    logout(request)
    return redirect("login")


class RootRedirect(RedirectView):
    pattern_name = None

    def get_redirect_url(self, *args, **kwargs):
        user = self.request.user
        if not user.is_authenticated:
            return "/login/"
        if getattr(user, "role", None) == "ADMIN":
            return "/analytics/"
        if getattr(user, "role", None) == "PROFESSOR":
            return "/projects/my/"
        return "/projects/my/"
