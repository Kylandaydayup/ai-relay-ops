# Secret Management

Do not commit real secrets.

Required production secrets:

```text
postgres:
  POSTGRES_PASSWORD

broker:
  DATABASE_URL
  CASDOOR_CLIENT_SECRET
  NEWAPI_ADMIN_ACCESS_TOKEN
  INTERNAL_API_KEY

new-api:
  SQL_DSN
  REDIS_CONN_STRING
  SESSION_SECRET
  CRYPTO_SECRET

edreamcrowd:
  SPRING_DATASOURCE_PASSWORD
  JASYPT_ENCRYPTOR_PASSWORD
  CASDOOR_ACCESS_KEY
  CASDOOR_ACCESS_SECRET
```

For the first production pass, create Kubernetes Secrets manually or from a private CI secret store.

```bash
kubectl create secret generic broker-secret -n platform \
  --from-literal=DATABASE_URL='postgresql+psycopg://...' \
  --from-literal=CASDOOR_CLIENT_SECRET='...' \
  --from-literal=NEWAPI_ADMIN_ACCESS_TOKEN='...'
```
