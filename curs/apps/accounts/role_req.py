from functools import wraps
from django.http import HttpResponseForbidden


def role_required(*roles):
    def dec(view):
        @wraps(view)
        def _wrap(request, *a, **kw):
            if (
                not request.user.is_authenticated
                or getattr(request.user, "role", None) not in roles
            ):
                return HttpResponseForbidden("Недостаточно прав")
            return view(request, *a, **kw)

        return _wrap

    return dec


class RoleRequiredMixin:
    allowed_roles: tuple[str, ...] = ()

    def dispatch(self, request, *args, **kwargs):
        if (
            not request.user.is_authenticated
            or getattr(request.user, "role", None) not in self.allowed_roles
        ):
            return HttpResponseForbidden("Недостаточно прав")
        return super().dispatch(request, *args, **kwargs)
