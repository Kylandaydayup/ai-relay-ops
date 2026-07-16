ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /deps

ARG PIP_INDEX_URL=https://pypi.org/simple

COPY pyproject.toml ./
COPY vendor ./vendor

RUN python -c 'import tomllib; from pathlib import Path; data = tomllib.loads(Path("pyproject.toml").read_text()); dependencies = data.get("project", {}).get("dependencies", []); assert dependencies, "missing project.dependencies in pyproject.toml"; print("\n".join(dependencies))' > requirements.txt

RUN python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" --upgrade pip \
    && python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" hatchling \
    && python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" -r requirements.txt \
    && if ls vendor/*.whl >/dev/null 2>&1; then \
      python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" vendor/*.whl; \
    fi
