ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml README.md ./
COPY provider_adapter ./provider_adapter
COPY vendor ./vendor

EXPOSE 8080

CMD ["uvicorn", "provider_adapter.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
