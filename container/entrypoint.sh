#!/usr/bin/env bash
# Geppetto container entrypoint: prepares the user identity and agent instructions,
# then runs the given command.
set -euo pipefail

uid="$(id -u)"
gid="$(id -g)"

# Give the host UID/GID a name so git, ssh and friends are happy.
if ! getent group "${gid}" >/dev/null; then
    echo "pinocchio:x:${gid}:" >> /etc/group
fi
if ! getent passwd "${uid}" >/dev/null; then
    echo "pinocchio:x:${uid}:${gid}:Pinocchio:${HOME}:/bin/bash" >> /etc/passwd
fi

mkdir -p "${HOME}"

# Shared instructions for every agent. Linked into each agent's global
# instruction location, so module repositories stay untouched.
instructions=/opt/geppetto/AGENTS.md
link_instructions() {
    local target="$1"
    mkdir -p "$(dirname "${target}")"
    # Do not overwrite a file the user maintains themselves.
    if [[ -L "${target}" || ! -e "${target}" ]]; then
        ln -sfn "${instructions}" "${target}"
    fi
}
link_instructions "${HOME}/.copilot/copilot-instructions.md"
command -v claude >/dev/null && link_instructions "${HOME}/.claude/CLAUDE.md"
command -v codex  >/dev/null && link_instructions "${HOME}/.codex/AGENTS.md"

# Puppet Core gems: Bundler credentials derived from the Forge API key.
if [[ -n "${PUPPET_FORGE_TOKEN:-}" ]]; then
    export BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM="forge-key:${PUPPET_FORGE_TOKEN}"
fi

exec "$@"
