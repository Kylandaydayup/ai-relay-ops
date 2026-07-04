#!/usr/bin/env python3
import argparse
import base64
import json
import subprocess
from pathlib import Path

import yaml


def read_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        data[key] = value
    return data


def kubectl_secret_value(namespace: str, secret_name: str, key: str) -> str:
    try:
        raw = subprocess.check_output(
            ["kubectl", "get", "secret", "-n", namespace, secret_name, "-o", "json"],
            text=True,
        )
    except Exception:
        return ""

    encoded = json.loads(raw).get("data", {}).get(key)
    if not encoded:
        return ""
    return base64.b64decode(encoded).decode()


def require(name: str, value: str) -> str:
    if not value:
        raise SystemExit(f"missing required value: {name}")
    return value


def _broker_newapi_database_url(sql_dsn: str) -> str:
    if sql_dsn.startswith("postgresql://"):
        return "postgresql+psycopg://" + sql_dsn.removeprefix("postgresql://")
    return sql_dsn


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Materialize a platform values.yaml with secret values from an env file and existing Kubernetes Secrets."
    )
    parser.add_argument("--input", required=True, help="Base values YAML")
    parser.add_argument("--output", required=True, help="Materialized values YAML")
    parser.add_argument("--secret-env", required=True, help="Secret env file")
    parser.add_argument("--namespace", default="platform", help="Kubernetes namespace for existing secrets")
    args = parser.parse_args()

    with Path(args.input).open() as f:
        values = yaml.safe_load(f)

    env = read_env(Path(args.secret_env))

    def secret(secret_name: str, key: str) -> str:
        return kubectl_secret_value(args.namespace, secret_name, key)

    postgres_password = require(
        "POSTGRES_PASSWORD",
        env.get("POSTGRES_PASSWORD") or secret("platform-postgres-secret", "POSTGRES_PASSWORD"),
    )
    casdoor_db_password = require("CASDOOR_DB_PASSWORD", env.get("CASDOOR_DB_PASSWORD", ""))
    edream_db_password = require(
        "EDREAMCROWD_DB_PASSWORD",
        env.get("EDREAMCROWD_DB_PASSWORD")
        or secret("edreamcrowd-backend-secret", "SPRING_DATASOURCE_PASSWORD"),
    )
    newapi_db_password = require("NEWAPI_DB_PASSWORD", env.get("NEWAPI_DB_PASSWORD", ""))
    broker_db_password = require("BROKER_DB_PASSWORD", env.get("BROKER_DB_PASSWORD", ""))

    newapi_sql_dsn = env.get("NEWAPI_SQL_DSN") or (
        f"postgresql://newapi:{newapi_db_password}@platform-postgres:5432/newapi"
    )
    newapi_redis = env.get("NEWAPI_REDIS_CONN_STRING") or secret(
        "relay-new-api-secret", "REDIS_CONN_STRING"
    )
    newapi_session = require(
        "NEWAPI_SESSION_SECRET",
        env.get("NEWAPI_SESSION_SECRET") or secret("relay-new-api-secret", "SESSION_SECRET"),
    )
    newapi_crypto = require(
        "NEWAPI_CRYPTO_SECRET",
        env.get("NEWAPI_CRYPTO_SECRET") or secret("relay-new-api-secret", "CRYPTO_SECRET"),
    )

    broker_database_url = env.get("BROKER_DATABASE_URL") or (
        f"postgresql+psycopg://broker:{broker_db_password}@platform-postgres:5432/broker_db"
    )
    broker_casdoor_database_url = env.get("BROKER_CASDOOR_DATABASE_URL") or (
        f"postgresql+psycopg://casdoor:{casdoor_db_password}@platform-postgres:5432/casdoor"
    )
    broker_casdoor_client_secret = env.get("BROKER_CASDOOR_CLIENT_SECRET") or secret(
        "relay-broker-secret", "CASDOOR_CLIENT_SECRET"
    )
    broker_newapi_token = require(
        "BROKER_NEWAPI_ADMIN_ACCESS_TOKEN",
        env.get("BROKER_NEWAPI_ADMIN_ACCESS_TOKEN")
        or env.get("NEWAPI_ADMIN_ACCESS_TOKEN")
        or secret("relay-broker-secret", "NEWAPI_ADMIN_ACCESS_TOKEN"),
    )
    broker_internal_key = require(
        "BROKER_INTERNAL_API_KEY",
        env.get("BROKER_INTERNAL_API_KEY") or secret("relay-broker-secret", "INTERNAL_API_KEY"),
    )
    moma_seedance_api_key = env.get("MOMA_SEEDANCE_API_KEY") or secret(
        "ai-provider-adapter-secret", "MOMA_SEEDANCE_API_KEY"
    )
    keyiyun_api_key = env.get("KEYIYUN_API_KEY") or secret(
        "ai-provider-adapter-secret", "KEYIYUN_API_KEY"
    )

    edream_jasypt = require(
        "EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD",
        env.get("EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD")
        or secret("edreamcrowd-backend-secret", "JASYPT_ENCRYPTOR_PASSWORD"),
    )
    edream_casdoor_access_key = env.get("EDREAMCROWD_CASDOOR_ACCESS_KEY") or secret(
        "edreamcrowd-backend-secret", "CASDOOR_ACCESS_KEY"
    )
    edream_casdoor_access_secret = env.get("EDREAMCROWD_CASDOOR_ACCESS_SECRET") or secret(
        "edreamcrowd-backend-secret", "CASDOOR_ACCESS_SECRET"
    )

    values["databaseInit"]["postgres"]["password"] = postgres_password
    values["databaseInit"]["rolePasswords"]["casdoor"] = casdoor_db_password
    values["databaseInit"]["rolePasswords"]["edreamcrowd"] = edream_db_password
    values["databaseInit"]["rolePasswords"]["newapi"] = newapi_db_password
    values["databaseInit"]["rolePasswords"]["broker"] = broker_db_password
    values["postgres"]["auth"]["password"] = postgres_password
    values["casdoor"]["config"]["dataSourceName"] = (
        f"user=casdoor password={casdoor_db_password} host=platform-postgres "
        "port=5432 sslmode=disable dbname=casdoor"
    )
    values["new-api"]["secret"]["SQL_DSN"] = newapi_sql_dsn
    values["new-api"]["secret"]["REDIS_CONN_STRING"] = newapi_redis
    values["new-api"]["secret"]["SESSION_SECRET"] = newapi_session
    values["new-api"]["secret"]["CRYPTO_SECRET"] = newapi_crypto
    values["broker"]["secret"]["DATABASE_URL"] = broker_database_url
    values["broker"]["secret"]["CASDOOR_CLIENT_SECRET"] = broker_casdoor_client_secret
    values["broker"]["secret"]["NEWAPI_ADMIN_ACCESS_TOKEN"] = broker_newapi_token
    values["broker"]["secret"]["NEWAPI_DATABASE_URL"] = _broker_newapi_database_url(newapi_sql_dsn)
    values["broker"]["secret"]["NEWAPI_REDIS_CONN_STRING"] = newapi_redis
    values["broker"]["secret"]["NEWAPI_CRYPTO_SECRET"] = newapi_crypto
    values["broker"]["secret"]["INTERNAL_API_KEY"] = broker_internal_key
    values["broker"]["secret"]["CASDOOR_DATABASE_URL"] = broker_casdoor_database_url
    if "ai-provider-adapter" in values:
        values["ai-provider-adapter"]["secret"]["MOMA_SEEDANCE_API_KEY"] = moma_seedance_api_key
        values["ai-provider-adapter"]["secret"]["KEYIYUN_API_KEY"] = keyiyun_api_key
    values["edreamcrowd"]["backend"]["secret"]["SPRING_DATASOURCE_PASSWORD"] = edream_db_password
    values["edreamcrowd"]["backend"]["secret"]["JASYPT_ENCRYPTOR_PASSWORD"] = edream_jasypt
    values["edreamcrowd"]["backend"]["secret"]["CASDOOR_ACCESS_KEY"] = edream_casdoor_access_key
    values["edreamcrowd"]["backend"]["secret"]["CASDOOR_ACCESS_SECRET"] = edream_casdoor_access_secret

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(yaml.safe_dump(values, allow_unicode=True, sort_keys=False))
    print(output)


if __name__ == "__main__":
    main()
