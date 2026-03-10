# This is the docker image we want to use as a base image
# If you have your own image, update the package url here
# By default, we will use the Adomi Odoo upstream image
#
# You can find the source code here:
# https://github.com/adomi-io/odoo
ARG ODOO_BASE_IMAGE="ghcr.io/adomi-io/odoo:19.0"
ARG ODOO_ENTERPRISE_REPOSITORY="https://github.com/odoo/enterprise"
ARG ODOO_ENTERPRISE_BRANCH="19.0"
ARG GIT_AUTH_FORMAT='https://x-access-token:%s@github.com\n'
ARG SPECIFIC_DATE=""
ARG SPECIFIC_HASH=""

FROM alpine:latest AS enterprise

RUN apk add --no-cache \
    git

WORKDIR /tmp/enterprise

RUN --mount=type=secret,id=ODOO_ENTERPRISE_GITHUB_TOKEN,target=/run/secrets/ODOO_ENTERPRISE_GITHUB_TOKEN,uid=0,gid=0,required=true \
    CREDS_FILE="$(mktemp)"; \
    TOKEN="$(cat /run/secrets/ODOO_ENTERPRISE_GITHUB_TOKEN)"; \
    test -n "${TOKEN}"; \
    printf "${GIT_AUTH_FORMAT}" "${TOKEN}" > "${CREDS_FILE}"; \
    if [[ -n "${SPECIFIC_DATE}" || -n "${SPECIFIC_HASH}" ]]; then \
        DEPTH_ARGS=""; \
    else \
        DEPTH_ARGS="--depth 1"; \
    fi; \
    git -c "credential.helper=store --file=${CREDS_FILE}" \
        -c credential.useHttpPath=false \
        -c core.askPass=/bin/true \
        -c credential.https://github.com.useHttpPath=false \
        clone \
        --branch "${ODOO_ENTERPRISE_BRANCH}" \
        --single-branch ${DEPTH_ARGS} \
        "${ODOO_ENTERPRISE_REPOSITORY}" .; \
    if [[ -n "${SPECIFIC_HASH}" ]]; then \
        git reset --hard "${SPECIFIC_HASH}"; \
    elif [[ -n "${SPECIFIC_DATE}" ]]; then \
        git config \
          --global \
          --add safe.directory /source; \
        REV_HASH="$(git rev-list -n 1 --before="${SPECIFIC_DATE}" "origin/${ODOO_ENTERPRISE_BRANCH}")"; \
        git reset --hard "${REV_HASH}"; \
    fi; \
    rm -f "${CREDS_FILE}"; \
    rm -rf .git

FROM ${ODOO_BASE_IMAGE} AS configuration_layer

# Set user to root so we can install dependencies
USER root

# Here, you can install python dependencies
# For example:
# RUN pip install  \
  #    python-slugify  \
  #    stripe  \
  #    mailerlite  \
  #    mailerlite \
  #    pika \
  #    betterproto \
  #    typeform \
  #    meilisearch

# Extend the layer with our python dependencies installed
FROM configuration_layer

# Odoo will run as a non-root user
# UID 1000 is the default user for Ubuntu
USER ubuntu

# We will work in the volumes directory, where our addons
# and mounted files are located
WORKDIR /volumes

# Copy our enterprise repo
COPY --from=enterprise /tmp/enterprise /volumes/enterprise

# Copy your configuration into the container
COPY config/odoo.conf /volumes/config/odoo.conf

# Copy extra addons for downstream images
COPY extra_addons /volumes/extra_addons

# Copy your custom addons into the container
COPY addons /volumes/addons