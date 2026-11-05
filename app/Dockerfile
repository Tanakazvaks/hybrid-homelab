FROM python:3.14-slim

WORKDIR /app
COPY app.py test_app.py ./

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

# Don't run as root inside the container
RUN useradd --system appuser
USER appuser

EXPOSE 8000
CMD ["python", "app.py"]
