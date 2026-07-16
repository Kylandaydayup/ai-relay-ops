ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml README.md ./
COPY relay_broker ./relay_broker
COPY newapi_compat_gateway ./newapi_compat_gateway

EXPOSE 8080

CMD ["uvicorn", "relay_broker.app:app", "--host", "0.0.0.0", "--port", "8080"]
