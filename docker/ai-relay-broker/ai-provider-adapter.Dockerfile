ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

ARG PIP_INDEX_URL=https://pypi.org/simple

RUN python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" --upgrade pip

COPY pyproject.toml README.md ./
COPY provider_adapter ./provider_adapter
COPY vendor ./vendor

RUN python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" fastapi "httpx>=0.28.0" "pydantic>=2.12.0" "uvicorn>=0.41.0" \
    && if ls vendor/maas_seedance_sdk-*.whl >/dev/null 2>&1; then \
      python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" vendor/maas_seedance_sdk-*.whl; \
    fi

EXPOSE 8080

CMD ["uvicorn", "provider_adapter.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
