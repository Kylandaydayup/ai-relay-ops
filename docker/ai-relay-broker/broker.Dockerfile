ARG PYTHON_BASE_IMAGE=python:3.12-slim

FROM ${PYTHON_BASE_IMAGE} AS deps
WORKDIR /deps
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
COPY pyproject.toml ./
COPY vendor ./vendor
RUN --mount=type=cache,target=/root/.cache/pip \
    python -c 'import tomllib; from pathlib import Path; data = tomllib.loads(Path("pyproject.toml").read_text()); dependencies = data.get("project", {}).get("dependencies", []); assert dependencies, "missing project.dependencies in pyproject.toml"; print("\n".join(dependencies))' > requirements.txt \
    && python -m pip install --prefix=/install --index-url "${PIP_INDEX_URL}" -r requirements.txt \
    && if ls vendor/*.whl >/dev/null 2>&1; then python -m pip install --prefix=/install --index-url "${PIP_INDEX_URL}" vendor/*.whl; fi

FROM ${PYTHON_BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=deps /install /usr/local
COPY pyproject.toml README.md ./
COPY relay_broker ./relay_broker
COPY newapi_compat_gateway ./newapi_compat_gateway

EXPOSE 8080

CMD ["uvicorn", "relay_broker.app:app", "--host", "0.0.0.0", "--port", "8080"]
