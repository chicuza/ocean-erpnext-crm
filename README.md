# ocean-erpnext-crm

Imagem custom **ERPNext v15 + Frappe CRM** para o Ocean (Amabile AI) na Railway.

## Por que este repo existe

O deploy do Ocean roda a imagem stock `frappe/erpnext:v15`, que contém apenas `frappe` + `erpnext`.
O diretório `apps/` do container **não está em volume persistente** (só `sites/` está), então
`bench get-app crm` dentro do container **não sobrevive a um redeploy**.

A forma documentada de adicionar um app em deploy containerizado é montar uma **imagem custom**
(ver `frappe_docker/images/layered/Containerfile`). É o que este repo faz.

## Versões fixadas (e por quê)

| App | Versão | Motivo |
|---|---|---|
| frappe | `version-15` (= 15.117.0) | igual à produção |
| erpnext | `v15.119.0` | igual à produção |
| crm | `v1.81.1` | **última tag que aceita `frappe >=15.0.0,<17.0.0`** |

> ⚠️ **NÃO usar o branch `main` do frappe/crm.**
> O `main` declara `frappe = ">=16.0.0-dev,<=17.0.0-dev"` — exige Frappe 16 e **quebraria** o Ocean, que roda v15.
> O comando padrão da doc (`bench get-app crm`) puxa `main`. Em site v15 é obrigatório fixar a tag.

Assim, o **único delta** em relação à imagem stock de produção é a adição do app `crm`.
Nenhum upgrade de frappe/erpnext embutido.

## Build

O Railway builda direto deste repo (`builder: DOCKERFILE`), sem necessidade de registry.

Local, para validar:

```bash
docker build --tag=ocean-erpnext-crm:v15 --file=Containerfile .
```

O `apps.json` entra por `COPY` em vez de BuildKit secret porque todos os repositórios são
**públicos** (não há token a proteger) e o builder do Railway não expõe `--secret`.

## Serviços que usam esta imagem

Os 4 serviços Frappe do projeto Railway `Ocean-nexterp` (todos a mesma imagem):
`erpnext-v15` (backend), `erpnext-v15-frontend` (nginx), `queue-worker`, `scheduler`.

`frappe/base:version-15` já inclui `nginx-entrypoint.sh`, por isso a mesma imagem serve o frontend.

## Rollback

Devolver `source.image` dos 4 serviços para `frappe/erpnext:v15` e restaurar o builder `RAILPACK`.
Baseline completo (start commands verbatim, IDs, volume) está registrado na base de conhecimento.
