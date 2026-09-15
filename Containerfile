# Ocean (Amabile AI) — ERPNext v15 + Frappe CRM + Frappe Helpdesk
#
# Baseado em frappe_docker/images/layered/Containerfile (procedimento oficial).
# Diferença deliberada: apps.json entra via COPY em vez de BuildKit secret,
# porque todos os repositórios são PÚBLICOS (não há token a proteger) e o
# builder do Railway não expõe --secret. A recomendação de usar secret existe
# para não vazar token de repo privado no histórico da imagem — não se aplica aqui.
#
# Versões FIXADAS para que o único delta em relação à produção seja a adição dos
# apps `telephony` e `helpdesk`:
#   frappe     version-15   (produção roda 15.117.0 / imagem atual 15.120.1)
#   erpnext    v15.119.0    (igual à produção)
#   crm        v1.81.1      (tag que aceita frappe >=15.0.0,<17.0.0)
#   telephony  develop      (único branch existente; não há tags no repo)
#   helpdesk   v1.30.1      (tag que aceita frappe >=15.116.1,<17.0.0)
#
# ATENCAO (1): o branch DEFAULT do frappe/crm e `develop` (nao `main`), e o develop
# exige frappe >=16.0.0-dev — QUEBRARIA o v15. Por isso crm fica fixado em tag.
# ATENCAO (2): nao existe --branch `main` no frappe/telephony; o repo so tem
# `develop`. helpdesk declara a dependencia `telephony >=0.0.1,<1.0.0`.
#
# ATENCAO (3) — POR QUE O BUILD DE ASSETS ACONTECE EM DUAS ETAPAS:
# O frontend do helpdesk (apps/helpdesk/desk, vite) importa `socketio_port` de
# sites/common_site_config.json EM TEMPO DE BUILD. Se a chave nao existir o
# Rollup falha com:
#   '"socketio_port" is not exported by "../../sites/common_site_config.json"'
# Por isso o `bench init` roda com --skip-assets, escrevemos um
# common_site_config.json minimo com socketio_port e SO ENTAO rodamos `bench build`.
# Em runtime o start command do servico sobrescreve esse config com os valores reais
# (bench set-config -g ...), entao o arquivo da imagem e apenas um placeholder de build.

ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_IMAGE_PREFIX=frappe

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS builder

ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_PATH=https://github.com/frappe/frappe

USER root
COPY apps.json /opt/frappe/apps.json
RUN chown frappe:frappe /opt/frappe/apps.json
USER frappe

# 1) bench init SEM assets (o helpdesk ainda nao tem o config de socketio_port)
RUN bench init \
      --apps_path=/opt/frappe/apps.json \
      --frappe-branch=${FRAPPE_BRANCH} \
      --frappe-path=${FRAPPE_PATH} \
      --no-procfile \
      --no-backups \
      --skip-redis-config-generation \
      --skip-assets \
      --verbose \
      /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr

# 2) config de build: socketio_port e obrigatorio para o vite do helpdesk
RUN cd /home/frappe/frappe-bench && \
    printf '{\n "socketio_port": 9000,\n "file_watcher_port": 6787\n}\n' \
      > sites/common_site_config.json

# 3) dependencias de frontend exigidas pelo build dos apps
#    (apps/frappe/ui e importado pelo desk do helpdesk e resolve `leaflet` de la)
RUN cd /home/frappe/frappe-bench/apps/frappe/ui && yarn install || true; \
    cd /home/frappe/frappe-bench && \
    for app in helpdesk telephony crm; do \
      if [ -f apps/$app/frontend/package.json ]; then \
        cd /home/frappe/frappe-bench/apps/$app/frontend && yarn install; \
      fi; \
      if [ -f apps/$app/desk/package.json ]; then \
        cd /home/frappe/frappe-bench/apps/$app/desk && yarn install; \
      fi; \
      cd /home/frappe/frappe-bench; \
    done

# 4) build de todos os assets
RUN cd /home/frappe/frappe-bench && bench build

FROM ${FRAPPE_IMAGE_PREFIX}/base:${FRAPPE_BRANCH} AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Move assets to image-layer storage
RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets && \
    rm -rf /home/frappe/frappe-bench/sites/assets

# NOTA: a instrucao VOLUME do Containerfile original do frappe_docker foi REMOVIDA.
# O builder da Railway rejeita o build com:
#   "dockerfile invalid: docker VOLUME at Line 58 is not supported, use Railway Volumes"
# Remover e seguro: VOLUME apenas declara volume anonimo do Docker. No Ocean, o volume
# real ja esta montado pela Railway em /home/frappe/frappe-bench/sites.

USER root
COPY resources/core/main-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

COPY resources/core/start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["start.sh"]
