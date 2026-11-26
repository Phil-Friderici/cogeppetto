# Geppetto

*A workshop where AI agents craft Puppet modules.*

Geppetto is the workshop: a Docker image with PDK, Litmus tooling, Git, the GitHub CLI
and AI agent CLIs. **Pinocchios** are the agent containers that work on your module
forks. They work on their own, but stay on Geppetto's strings: a token that only reaches
your own forks, a protected default branch, and your review before anything goes
upstream. And when a Pinocchio fibs, its nose grows. That is what validate, unit and
acceptance tests are for.

```
geppetto start puppetlabs-motd
  └─ clones your fork, picks the PDK version from metadata.json,
     starts pinocchio-puppetlabs-motd and attaches GitHub Copilot CLI

inside: pm branch issue-42 → edit → pm validate → pm unit → pm acceptance → pm push
you:    review the agent/issue-42 branch on GitHub and open the PR upstream
```

See [docs/concept.md](docs/concept.md) for the design and its reasoning.

## Requirements

- A dedicated Linux host (e.g. Ubuntu on AWS) with Docker Engine and BuildKit.
  Your user must be in the `docker` group.
- `git`, `curl`, `jq` and, for `geppetto protect`, the GitHub CLI `gh` on the host.
- A **Forge API key** with Puppet Core access (`PUPPET_FORGE_TOKEN`).
- A GitHub **fine-grained personal access token** (`GH_TOKEN`):
  resource owner = your account, repository access = only your module forks,
  permission **Contents: Read and write**, nothing else.
- An account for the agent you use (e.g. GitHub Copilot).

> **Security note:** Pinocchios get the host's Docker socket so Litmus can start test
> containers. Anyone with access to that socket is effectively root on the host. Run
> Geppetto only on a host dedicated to this purpose and share it only with people you
> trust.

## Setup

```bash
git clone https://github.com/Phil-Friderici/geppetto.git ~/geppetto-src
ln -s ~/geppetto-src/bin/geppetto ~/.local/bin/geppetto   # or add bin/ to PATH

geppetto init            # creates ~/geppetto/{workspace,home,.env}
$EDITOR ~/geppetto/.env  # tokens, your GitHub account, git identity
geppetto build           # image for the default PDK (GEPPETTO_DEFAULT_PDK)
```

For each module: fork it on GitHub into your account, add the fork to the token's
repository list, then protect its default branch. The upstream repository does not need
to be configured: `geppetto start` reads it from the fork's parent on GitHub, so forks of
`puppetlabs`, `voxpupuli` or anyone else work the same way.

```bash
gh auth login                       # once, with your own account
geppetto protect puppetlabs-motd    # ruleset: no direct push, no force push, no deletion
```

The ruleset applies to everyone, including you, because the agent's token acts as you.
Changes reach your fork's default branch only through pull requests. That is fine for
this workflow: agents branch from the **upstream** default branch, so your fork's
default branch does not need to be up to date.

## Daily use

```bash
geppetto start puppetlabs-motd                 # task name = module name
geppetto start puppetlabs-motd --name issue-42 # second, independent checkout
geppetto start puppetlabs-motd --pdk 4.0.1     # override the PDK version
geppetto start puppetlabs-motd --agent shell   # just a shell
geppetto start my-module --upstream someone    # repo is a copy, not a GitHub fork
geppetto list
geppetto attach issue-42                       # reattach the agent
geppetto shell issue-42
geppetto stop issue-42                         # container goes, workspace stays
geppetto update                                # rebuild images: latest base and agents
```

Leaving the agent (Ctrl-D / exit) keeps the container running; `attach` brings you back.

### Inside a Pinocchio: `pm`

| Command | What it does |
|---|---|
| `pm info` | Module, PDK versions (module vs. container), gem source, branch, remotes |
| `pm setup` | Fetch upstream, disable pushes to upstream, install the bundle |
| `pm branch TOPIC` | Create `agent/TOPIC` from the upstream default branch |
| `pm validate` | `pdk validate` |
| `pm unit` | `pdk test unit` |
| `pm acceptance` | Litmus: provision → install agent → install module → tests → tear down |
| `pm pdk-update [--noop]` | Move the module to the container's PDK, then validate and unit |
| `pm push` | Push the `agent/*` branch to your fork (with a secret check) |

`pm acceptance` options: `--set NAME` (set from `provision.yaml`), `--inventory FILE`
(test existing machines), `--collection NAME` (default `puppetcore8` with a Forge key),
`--keep` (no tear down).

## Where things live

| Host | In the container | Content |
|---|---|---|
| `~/geppetto/workspace/<task>` | `/workspace/<task>` | Checkout of your fork |
| `~/geppetto/home` | `/home/pinocchio` | Agent logins and sessions, PDK and gem caches |
| `~/geppetto/.env` | environment | Tokens and settings |

Images contain only programs. Rebuilding or removing containers never touches your work.

## Commits and attribution

Agents commit with **your** git identity (`GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` in
`.env`), because you review the work and open the pull request; GitHub, CLA and DCO
checks then attribute the commits to you. Every agent commit ends with a trailer such as
`Assisted-by: GitHub Copilot CLI (Geppetto)`, so reviewers can see that an agent was
involved. If your GitHub settings block pushes that expose your email address, use your
`users.noreply.github.com` address instead.

## PDK versions

Each PDK version gets its own image (`geppetto:pdk-<version>`). `geppetto start` reads
`pdk-version` from the module's `metadata.json` and builds the image on first use.
To move a module to a newer PDK:

```bash
geppetto start puppetlabs-motd --pdk 4.0.1
pm pdk-update --noop    # preview
pm pdk-update           # update, bundle, validate, unit
```

## Agents

Copilot CLI is installed by default. Add others with `GEPPETTO_AGENTS=copilot,claude,codex`
in `.env` and rebuild. [AGENTS.md](AGENTS.md) holds the shared instructions; the entrypoint
links it into each agent's global instruction file (`~/.copilot/copilot-instructions.md`,
`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so module repositories stay untouched.
On first start, log in to the agent (Copilot: `/login`); the login persists in
`~/geppetto/home`.

## Status

First version, not yet tested on a real host. Reference module for testing:
`puppetlabs-motd`.
