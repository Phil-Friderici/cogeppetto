# syntax=docker/dockerfile:1.7
#
# Geppetto workshop image. Built by `bin/geppetto build`; one image per PDK version
# (tag geppetto:pdk-<version>).
#
#   PDK_VERSION  PDK release to install, e.g. 4.0.1 or 3.5.1 (required)
#   AGENTS       comma-separated agent CLIs to install: copilot, claude, codex
#
# The Puppet Core APT credentials are passed as the BuildKit secret
# `puppetcore_apt_auth` and are only mounted in the download stage.

ARG UBUNTU_VERSION=24.04

# ---------------------------------------------------------------------------
# Stage 1: download the PDK package (the only stage that sees the credentials)
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS pdk-download

ARG PDK_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN test -n "${PDK_VERSION}" || { echo "PDK_VERSION build argument is required" >&2; exit 1; }

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl \
    && . /etc/os-release \
    # Puppet Core repository (authenticated, current PDK releases)
    && curl -fsSL -o /tmp/puppet8-release.deb \
        "https://apt-puppetcore.puppet.com/public/puppet8-release-${VERSION_CODENAME}.deb" \
    && dpkg -i /tmp/puppet8-release.deb \
    # Public Puppet tools repository (older open source PDK releases), if it exists
    && if curl -fsSL -o /tmp/puppet-tools-release.deb \
            "https://apt.puppet.com/puppet-tools-release-${VERSION_CODENAME}.deb"; then \
           dpkg -i /tmp/puppet-tools-release.deb; \
       else \
           echo "No public puppet-tools repository for ${VERSION_CODENAME}; using Puppet Core only."; \
       fi \
    && rm -f /tmp/*.deb

RUN --mount=type=secret,id=puppetcore_apt_auth,target=/etc/apt/auth.conf.d/puppetcore.conf,required=true \
    apt-get update \
    && cd /tmp \
    # Package versions look like 4.0.1.1-1noble; pick the newest matching PDK_VERSION.
    && pkg_version="$(apt-cache madison pdk | awk '{print $3}' \
           | grep -E "^${PDK_VERSION}([.-]|$)" | sort -V | tail -n 1)" \
    && if [ -z "${pkg_version}" ]; then \
           echo "PDK ${PDK_VERSION} not found. Available versions:" >&2; \
           apt-cache madison pdk >&2; \
           exit 1; \
       fi \
    && echo "Downloading pdk=${pkg_version}" \
    && apt-get download "pdk=${pkg_version}" \
    && mv /tmp/pdk_*.deb /tmp/pdk.deb

# ---------------------------------------------------------------------------
# Stage 2: the workshop
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS workshop

ARG PDK_VERSION
ARG AGENTS=copilot
ARG NODE_MAJOR=22
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="geppetto" \
      org.opencontainers.image.description="A workshop where AI agents craft Puppet modules" \
      geppetto.pdk-version="${PDK_VERSION}" \
      geppetto.agents="${AGENTS}"

# Base tools. build-essential is needed for native gem extensions.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential ca-certificates curl git gnupg jq less openssh-client \
        procps unzip vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# Third-party APT repositories: Docker CLI, GitHub CLI, Node.js
RUN install -d -m 0755 /etc/apt/keyrings \
    && . /etc/os-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install --yes --no-install-recommends docker-ce-cli gh nodejs \
    && rm -rf /var/lib/apt/lists/*

# PDK (downloaded in stage 1, installed here without any credentials)
COPY --from=pdk-download /tmp/pdk.deb /tmp/pdk.deb
RUN apt-get update \
    && apt-get install --yes --no-install-recommends /tmp/pdk.deb \
    && rm -rf /tmp/pdk.deb /var/lib/apt/lists/* \
    && pdk --version

# Agent CLIs (latest by default; rebuild with `geppetto update` to refresh)
RUN set -eu; \
    for agent in $(echo "${AGENTS}" | tr ',' ' '); do \
        case "${agent}" in \
            copilot) npm install --global @github/copilot ;; \
            claude)  npm install --global @anthropic-ai/claude-code ;; \
            codex)   npm install --global @openai/codex ;; \
            *) echo "Unknown agent: ${agent}" >&2; exit 1 ;; \
        esac; \
    done; \
    npm cache clean --force

# Git: authenticate to GitHub with GH_TOKEN through the gh credential helper
RUN git config --system credential.https://github.com.helper '' \
    && git config --system --add credential.https://github.com.helper '!gh auth git-credential' \
    && git config --system init.defaultBranch main

# The container runs with the host user's UID/GID, which has no passwd entry in the
# image (the image's default "ubuntu" user is removed so the name is free). The
# entrypoint adds one at startup, so /etc/passwd and /etc/group must be writable.
# This is acceptable: the container belongs to a single user.
RUN (userdel --remove ubuntu 2>/dev/null || true) \
    && chmod 0666 /etc/passwd /etc/group \
    && install -d -m 0777 /home/pinocchio /workspace

COPY AGENTS.md /opt/geppetto/AGENTS.md
COPY --chmod=0755 bin/pm /usr/local/bin/pm
COPY --chmod=0755 container/entrypoint.sh /usr/local/bin/geppetto-entrypoint

ENV HOME=/home/pinocchio \
    LANG=C.UTF-8 \
    GEPPETTO_PDK_VERSION=${PDK_VERSION} \
    PATH=/opt/puppetlabs/pdk/bin:${PATH}

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/geppetto-entrypoint"]
CMD ["bash"]
