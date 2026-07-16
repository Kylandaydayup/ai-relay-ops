ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml README.md ./
COPY newapi_compat_gateway ./newapi_compat_gateway

EXPOSE 8080

CMD ["uvicorn", "newapi_compat_gateway.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
