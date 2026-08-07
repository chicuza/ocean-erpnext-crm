# Ocean (Amabile AI) — ERPNext v15 + Frappe CRM
#
# Baseado em frappe_docker/images/layered/Containerfile (procedimento oficial).
# Diferença deliberada: apps.json entra via COPY em vez de BuildKit secret,
# porque todos os repositórios são PÚBLICOS (não há token a proteger) e o
# builder do Railway não expõe --secret. A recomendação de usar secret existe
# para não vazar token de repo privado no histórico da imagem — não se aplica aqui.
#
# Versões FIXADAS para que o único delta em relação à produção atual
# (frappe/erpnext:v15) seja a adição do app `crm`:
#   frappe   version-15   (produção roda 15.117.0)
#   erpnext  v15.119.0    (igual à produção)
#   crm      v1.81.1      (última tag que aceita frappe >=15.0.0,<17.0.0;
#                          o branch `main` exige >=16.0.0-dev e QUEBRARIA o v15)

ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_IMAGE_PREFIX=frappe

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS builder

ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_PATH=https://github.com/frappe/frappe

USER root
COPY apps.json /opt/frappe/apps.json
RUN chown frappe:frappe /opt/frappe/apps.json
USER frappe

RUN bench init \
      --apps_path=/opt/frappe/apps.json \
      --frappe-branch=${FRAPPE_BRANCH} \
      --frappe-path=${FRAPPE_PATH} \
      --no-procfile \
      --no-backups \
      --skip-redis-config-generation \
      --verbose \
      /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    echo "{}" > sites/common_site_config.json && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM ${FRAPPE_IMAGE_PREFIX}/base:${FRAPPE_BRANCH} AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Move assets to image-layer storage
RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets && \
    rm -rf /home/frappe/frappe-bench/sites/assets

VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/logs" \
]

USER root
COPY resources/core/main-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

COPY resources/core/start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["start.sh"]
