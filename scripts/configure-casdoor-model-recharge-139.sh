#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"

owner="${CASDOOR_PRODUCT_OWNER:-edream}"
product_name="${CASDOOR_MODEL_RECHARGE_PRODUCT:-model-quota}"
display_name="${CASDOOR_MODEL_RECHARGE_DISPLAY_NAME:-易苗梦剧场-模型额度充值}"
detail="${CASDOOR_MODEL_RECHARGE_DETAIL:-易苗梦剧场内置模型额度充值}"
description="${CASDOOR_MODEL_RECHARGE_DESCRIPTION:-充值后可使用客户端内置模型能力}"
tag="${CASDOOR_MODEL_RECHARGE_TAG:-模型充值}"
currency="${CASDOOR_MODEL_RECHARGE_CURRENCY:-CNY}"
price="${CASDOOR_MODEL_RECHARGE_DEFAULT_PRICE:-9.8}"
quantity="${CASDOOR_MODEL_RECHARGE_QUANTITY:-999999}"
image="${CASDOOR_MODEL_RECHARGE_IMAGE:-https://edream-public-1436584532.cos.ap-guangzhou.myqcloud.com/icon.jpg}"
providers="${CASDOOR_MODEL_RECHARGE_PROVIDERS:-[\"wechat-provider\"]}"
recharge_options="${CASDOOR_MODEL_RECHARGE_OPTIONS:-[9.8,98,198,398,998]}"
disable_custom_recharge="${CASDOOR_MODEL_RECHARGE_DISABLE_CUSTOM:-false}"
success_url="${CASDOOR_MODEL_RECHARGE_SUCCESS_URL:-}"

export KUBECONFIG="$kubeconfig"

echo "configuring Casdoor model recharge product: ${owner}/${product_name}"

kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -v ON_ERROR_STOP=1 <<SQL
INSERT INTO product (
  owner,
  name,
  created_time,
  display_name,
  image,
  detail,
  description,
  tag,
  currency,
  price,
  quantity,
  sold,
  is_recharge,
  recharge_options,
  disable_custom_recharge,
  providers,
  success_url,
  state
) VALUES (
  '${owner}',
  '${product_name}',
  to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'),
  '${display_name}',
  '${image}',
  '${detail}',
  '${description}',
  '${tag}',
  '${currency}',
  '${price}'::double precision,
  '${quantity}'::integer,
  0,
  true,
  '${recharge_options}',
  '${disable_custom_recharge}'::boolean,
  '${providers}',
  '${success_url}',
  'Published'
)
ON CONFLICT (owner, name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  image = EXCLUDED.image,
  detail = EXCLUDED.detail,
  description = EXCLUDED.description,
  tag = EXCLUDED.tag,
  currency = EXCLUDED.currency,
  price = EXCLUDED.price,
  quantity = EXCLUDED.quantity,
  is_recharge = EXCLUDED.is_recharge,
  recharge_options = EXCLUDED.recharge_options,
  disable_custom_recharge = EXCLUDED.disable_custom_recharge,
  providers = EXCLUDED.providers,
  success_url = EXCLUDED.success_url,
  state = EXCLUDED.state;
SQL

kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -P pager=off \
    -c "SELECT owner, name, display_name, price, is_recharge, recharge_options, disable_custom_recharge, providers, state FROM product WHERE owner = '${owner}' AND name = '${product_name}';"

echo "Casdoor model recharge URL: http://auth.nexushome.top/products/${owner}/${product_name}/buy"
