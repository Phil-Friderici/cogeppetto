# CoGeppetto

*A workshop where AI agents craft Puppet modules.*

"Co" as in co-author: agents do the work, you review it and decide what goes upstream.
Inside CoGeppetto, **Geppetto** is the workshop and its command (`geppetto`): a Docker image with PDK, Litmus tooling, Git, the GitHub CLI
and AI agent CLIs. **Pinocchios** are the agent containers that work on your module
forks. They work on their own, but stay on Geppetto's strings: a token that only reaches
your own forks, a protected default branch, and your review before anything goes
upstream. And when a Pinocchio fibs, its nose grows. That is what validate, unit and
acceptance tests are for.

```
geppetto start puppetlabs-motd
  └─ clones your fork, picks the PDK version from metadata.json,
     starts pinocchio-puppetlabs-motd and attaches GitHub Copilot CLI

inside: pm branch issue-42 → edit → pm validate → pm unit → pm apply → pm acceptance
        → pm report → pm push
you:    geppetto pr issue-42 → review the branch and the description, create the PR
```

See [docs/concept.md](docs/concept.md) for the design and its reasoning.

## Requirements

- A dedicated Linux host (e.g. Ubuntu on AWS) with Docker Engine and BuildKit.
  Your user must be in the `docker` group.
- `git`, `curl`, `jq` and, for `geppetto protect`, the GitHub CLI `gh` on the host.
- A **Forge API key** with Puppet Core access (`PUPPET_FORGE_TOKEN`).
- A GitHub **fine-grained personal access token** (`GH_TOKEN`):
  resource owner = your account, repository access = only your module forks,
  permissions **Contents: Read and write** and **Workflows: Read and write**, nothing
  else (Workflows is needed to push changes to `.github/workflows/`, e.g. after
  `pm pdk-update`). Use a dedicated token for CoGeppetto.
- An account for the agent you use (e.g. GitHub Copilot). For Copilot, a second
  fine-grained token with the account permission **Copilot Requests**
  (`COPILOT_GITHUB_TOKEN`) avoids logging in again after every rebuild.

> **Security note:** Pinocchios get the host's Docker socket so Litmus can start test
> containers. Anyone with access to that socket is effectively root on the host. Run
> CoGeppetto only on a host dedicated to this purpose and share it only with people you
> trust.

## Setup

```bash
git clone https://github.com/Phil-Friderici/cogeppetto.git ~/cogeppetto-src
ln -s ~/cogeppetto-src/bin/geppetto ~/.local/bin/geppetto   # or add bin/ to PATH

geppetto init            # creates ~/cogeppetto/{workspace,home,.env}
$EDITOR ~/cogeppetto/.env  # tokens, your GitHub account, git identity
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
geppetto start puppetlabs-motd -- --yolo       # extra arguments for the agent
geppetto start my-module --upstream someone    # repo is a copy, not a GitHub fork
geppetto list
geppetto attach issue-42                       # reattach the agent
geppetto shell issue-42
geppetto stop issue-42                         # container goes, workspace stays
geppetto pr issue-42                           # link to create the PR with the agent's description
geppetto update                                # rebuild images: latest base and agents
geppetto cleanup                               # remove leftover Litmus test containers
```

Leaving the agent (Ctrl-D / exit) keeps the container running; `attach` brings you back.

### Inside a Pinocchio: `pm`

| Command | What it does |
|---|---|
| `pm info` | Module, PDK versions (module vs. container), gem source, branch, remotes |
| `pm setup` | Fetch upstream, disable pushes to upstream, install the bundle |
| `pm branch TOPIC --model M` | Create `cogeppetto/TOPIC-M` from the upstream default branch; the agent names its own model |
| `pm validate` | `pdk validate` |
| `pm unit` | `pdk test unit` |
| `pm target up` | Start a test machine (Litmus) with Puppet and the module installed |
| `pm apply FILE.pp` / `-e '…'` | Reinstall the module, `puppet apply` on the test machine, then a second run as idempotence check (`--noop` to preview) |
| `pm target exec '…'` / `pm target down` | Inspect the test machine / remove it |
| `pm acceptance` | Litmus: provision → install agent → install module → tests → tear down |
| `pm pdk-update [--noop]` | Move the module to the container's PDK, then validate and unit |
| `pm results` | Show the recorded test results for the current files |
| `pm report` | Write the pull request description (English) from the module's PR template and the recorded test results |
| `pm push` | Push the `cogeppetto/*` branch to your fork: secret check; needs passing validate/unit and a report for HEAD |

`pm sets` shows which sets and images from `provision.yaml` are usable here (Docker images
that exist in the registry; `abs` and `provision_service` are Puppet internal, `vagrant`
needs a backend that does not exist yet).

`pm acceptance` reports a status per image: `OK`, `TEST FAILED` (the module),
`PROVISION FAILED`, `AGENT FAILED`, `MISSING` (infrastructure, not caused by the module).
Exit code 0 means all tested images passed, 1 test failures, 3 infrastructure problems only.
Each image is provisioned and gets its agent on its own, so one broken image does not stop
the others; the tests then run in parallel on all remaining machines.

Options: `--all-sets` (every Docker set, one after another), `--set NAME` (set from `provision.yaml`), `--image IMAGE` (a
Docker image instead of a set, without changing `provision.yaml`), `--inventory FILE`
(test existing machines), `--collection NAME` (default `puppetcore8` with a Forge key),
`--keep` (no tear down).

## Where things live

| Host | In the container | Content |
|---|---|---|
| `~/cogeppetto/workspace/<task>` | `/workspace/<task>` | Checkout of your fork |
| `~/cogeppetto/home` | `/home/pinocchio` | Agent logins and sessions, PDK and gem caches |
| `~/cogeppetto/.env` | environment | Tokens and settings |

Images contain only programs. Rebuilding or removing containers never touches your work.

## Commits and attribution

Agents commit with **your** git identity (`GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` in
`.env`), because you review the work and open the pull request; GitHub, CLA and DCO
checks then attribute the commits to you. Every agent commit ends with a trailer such as
`Assisted-by: GitHub Copilot CLI, gpt6-luna (CoGeppetto)`, so reviewers can see that an agent was
involved. If your GitHub settings block pushes that expose your email address, use your
`users.noreply.github.com` address instead.

## Pull requests

The agent never opens a pull request. It writes the description with `pm report`: the
module's pull request template, filled in by the agent in English for the maintainers,
plus the test results that `pm` recorded itself (with the exact files each run tested,
so the numbers cannot be made up or stale). The checklist items for spec tests,
acceptance tests and manual verification are ticked from those results. `pm push`
refuses to push without passing validate/unit results and a description for HEAD.

On the host, `geppetto pr <task>` prints a link to GitHub's compare page with title and
description filled in. Review both there and click *Create pull request* yourself. Long
descriptions do not fit in a link; then paste `.git/cogeppetto/pr.md` from the checkout.

## PDK versions

Each PDK version gets its own image (`geppetto:pdk-<version>`). `geppetto start` reads
`pdk-version` from the module's `metadata.json` and builds the image on first use.

The gem source follows the PDK version: PDK 3.x ships Puppet 8.10.0, the last public
release, and uses the public gems from rubygems.org; PDK 4.x ships Puppet 9 (default) and
8.22 and uses Puppet Core. `pm info` shows the active source; `GEPPETTO_GEM_SOURCE` in
`.env` overrides it. With PDK 4.x, tests run against Puppet 9 by default (the target for all modules);
add `--puppet-version 8` to test Puppet 8 as well, e.g. `pm unit --puppet-version 8`.
To move a module to a newer PDK:

```bash
geppetto start puppetlabs-motd --pdk 4.0.1
pm pdk-update --noop    # preview
pm pdk-update           # update, bundle, validate, unit
```

## Agents

Default arguments per agent come from `.env` (`GEPPETTO_COPILOT_ARGS`, `GEPPETTO_CLAUDE_ARGS`,
…); `geppetto start … -- ARGS` and `geppetto attach TASK -- ARGS` add more for one session.
`--yolo` (Copilot runs every tool without asking) is deliberately not a default; see the
example in `.env.example` and decide yourself.

Copilot CLI is installed by default. Add others with `GEPPETTO_AGENTS=copilot,claude,codex`
in `.env` and rebuild. [AGENTS.md](AGENTS.md) holds the shared instructions; the entrypoint
links it into each agent's global instruction file (`~/.copilot/copilot-instructions.md`,
`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so module repositories stay untouched.
For Copilot, set `COPILOT_GITHUB_TOKEN` in `.env` (fine-grained PAT owned by your personal
account with the **Copilot Requests** permission). Copilot CLI checks `COPILOT_GITHUB_TOKEN`,
then `GH_TOKEN`; without its own token it would use the Git token, which has no Copilot
permission. Other agents: log in on first start; the login persists in `~/cogeppetto/home`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `pm push`: `Permission to <user>/<module>.git denied to <user>` (403) | The token cannot write to this fork. Check the token on GitHub: *Repository access* must list exactly this fork (similar names are easy to mix up), *Contents* must be *Read and write*, and the *Resource owner* must be your account. Test with `git push --dry-run origin HEAD:refs/heads/cogeppetto/test`. |
| `pm push` rejected: `refusing to allow a Personal Access Token to create or update workflow` | The token needs *Workflows: Read and write*. |
| `git push origin HEAD:main`: `GH013: Repository rule violations` | Expected: `geppetto protect` blocks direct pushes to the default branch. |
| `Authentication is required for rubygems-puppetcore.puppet.com` | `PUPPET_FORGE_TOKEN` missing or `~/.gemfile` not managed by CoGeppetto (`pm info` warns). |
| Copilot asks for `/login` again after every rebuild | Environment tokens override Copilot's stored login, and `GH_TOKEN` (the Git token) has no Copilot permission. Set `COPILOT_GITHUB_TOKEN` in `.env` (Copilot Requests permission), then `geppetto stop` / `start`. |
| `docker ps` shows `litmusimage/*` containers after a run | Litmus leaves a container behind when provisioning fails after the container started (e.g. SSH setup). `pm` removes these itself since 2026-11-26; for older leftovers run `geppetto cleanup`. |
| `Could not find compatible versions … bolt … puppet >= 8.11` | Puppet Core gems with PDK 3.x; leave `GEPPETTO_GEM_SOURCE` on `auto` (public gems for PDK 3.x). |

Changes to `.env` take effect after `geppetto stop <task>` and `geppetto start …`; changes to
a token's settings on GitHub take effect immediately.

## Status

Verified end to end on an AWS host with `puppetlabs-motd` (PDK 3.5.1): build, start,
validate, unit, acceptance (Docker), push, ruleset. Next: agent tasks with Copilot and
PDK 4.0.1 / Puppet 9.
