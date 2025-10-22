from django.shortcuts import render


def error_403(request, exception=None):
    msg = ""
    if exception and getattr(exception, "args", None):
        msg = exception.args[0]
    ctx = {
        "title": "Нет доступа",
        "message": msg or "Недостаточно прав для просмотра этой страницы.",
    }
    return render(request, "403.html", ctx, status=403)
