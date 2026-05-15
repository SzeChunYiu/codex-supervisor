# Running codex-supervisor on LUNARC

How to use the shared codex toolchain installed under
`/projects/hep/fs10/shared/codex-tooling/` on the LUNARC HPC cluster (Lund
University). The toolchain is shared across all HEP-group users; credentials
are per-user, isolated to `per-user/$USER/`.

## Why use LUNARC for codex-supervisor

- Each compute node has 40+ CPUs and 200+ GB RAM — easily 20-30 codex panes
  per session vs. the ~6-8 cap on a 16 GB Mac.
- Heavy worker tasks (Geant4 builds, SLURM submissions, large pytest runs)
  execute *natively* on LUNARC — no rsync round-trip from local.
- 5-day allocations on the `hep` partition mean the supervisor stays alive
  across long compaction/iteration cycles without local babysitting.

The local Mac is still the right place for thesis-critical and
NNBAR-production work; LUNARC is right for exploratory R&D (G4 acceleration,
MCAccel competitor benchmarks, etc.) that benefits from parallelism.

## Layout

```
/projects/hep/fs10/shared/codex-tooling/
├── nvm/                       755   shared — Node Version Manager
├── npm-global/                755   shared — global npm packages
│   └── bin/{codex,claude}
├── npm-cache/                 755   shared — npm download cache (read-mostly)
├── supervisor/                755   shared — codex-supervisor.sh + csup-dashboard
│   ├── codex-supervisor.sh
│   └── csup-dashboard
├── env-shared.sh              755   shared — one-liner any user sources
└── per-user/                  755   shared — parent of user-private dirs
    └── <username>/            700   user-private
        ├── codex-home/        700   credentials (auth.json, .credentials.json, config.toml)
        ├── .npmrc             600   per-user npm config
        ├── run/               700   supervisor session state, sockets, logs
        └── csup/hosts.toml    600   host inventory used when running csup on LUNARC
```

Binaries are shared. Credentials and per-session state are per-user.

## One-time setup (per new user)

A user who has never run codex on LUNARC before:

1. **SSH to LUNARC**: `ssh lunarc` (assuming `lunarc-init.sh` has been run)
2. **Source the shared env**:
   ```bash
   source /projects/hep/fs10/shared/codex-tooling/env-shared.sh
   ```
3. **Authenticate codex** (first time only — opens a browser URL):
   ```bash
   codex login
   ```
   Or copy credentials from a local install (see "Importing existing auth").
4. **Verify**:
   ```bash
   codex --version
   claude --version
   ```

## Running a supervisor session on a compute node

The login node is NOT for compute; use a SLURM allocation.

1. **Submit a holder allocation** (5-day hep partition):
   ```bash
   sbatch --partition=hep --time=5-00:00:00 --nodes=1 --cpus-per-task=40 \
          --mem=200G --account=hep2023-1-3 \
          --wrap="echo NODE \$HOSTNAME JOBID \$SLURM_JOB_ID; sleep 432000"
   ```
   Note the job ID and the node name (from `squeue -j <jobid>` or the
   `--output` log).

2. **Attach to the allocation via srun**:
   ```bash
   srun --jobid=<jobid> --overlap --pty bash
   ```

3. **Source env and start supervisor**:
   ```bash
   source /projects/hep/fs10/shared/codex-tooling/env-shared.sh
   cd /path/to/your/project/with/.codex-supervisor.toml
   CODEX_SUPERVISOR_SESSION=my-session-name \
   CODEX_SUPERVISOR_PROMPTS=path/to/prompts.txt \
   CODEX_SUPERVISOR_MAX_PANES=24 \
   /projects/hep/fs10/shared/codex-tooling/supervisor/codex-supervisor.sh start --no-attach
   ```

4. **(Optional) Stream the dashboard to local**:
   ```bash
   # Inside the allocation, expose the loopback dashboard on the node's interface:
   srun --jobid=<jobid> --overlap socat \
     TCP-LISTEN:7780,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:7777 &

   # From your local machine:
   ssh -L 7778:<nodename>:7780 lunarc
   # Then open http://localhost:7778 locally
   ```

## env-shared.sh

This single file is the entry point for every user:

```bash
#!/usr/bin/env bash
# Source this to use the shared codex toolchain on LUNARC.
# /projects/hep/fs10/shared/codex-tooling/env-shared.sh

TOOLS=/projects/hep/fs10/shared/codex-tooling
USER_DIR=$TOOLS/per-user/$USER

# Create user-private dirs lazily
mkdir -p $USER_DIR/codex-home $USER_DIR/run $USER_DIR/csup

# Node Version Manager (shared)
export NVM_DIR=$TOOLS/nvm
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 >/dev/null 2>&1 || nvm install 20

# npm config — global prefix is shared but read-only-ish;
# user-specific config lives in per-user dir
export NPM_CONFIG_USERCONFIG=$USER_DIR/.npmrc
export NPM_CONFIG_CACHE=$TOOLS/npm-cache

# Codex CLI on PATH
export PATH=$TOOLS/npm-global/bin:$PATH

# Codex looks here for auth.json / .credentials.json / config.toml
export CODEX_HOME=$USER_DIR/codex-home

# Supervisor binaries on PATH
export PATH=$TOOLS/supervisor:$PATH

# Supervisor writes session state under per-user dir to avoid collisions
export CODEX_SUPERVISOR_RUN_DIR=$USER_DIR/run

# csup reads host inventory from the shared filesystem, not quota-limited HOME
export CSUP_HOSTS_FILE=$USER_DIR/csup/hosts.toml
```

## Updating shared Codex / Claude Code binaries

Check the registry first from any machine with npm:

```bash
npm view @openai/codex version
npm view @anthropic-ai/claude-code version
```

Then update the shared LUNARC binaries with:

```bash
source /projects/hep/fs10/shared/codex-tooling/env-shared.sh
npm install -g --prefix=/projects/hep/fs10/shared/codex-tooling/npm-global \
  @openai/codex@latest @anthropic-ai/claude-code@latest
codex --version
claude --version
```

Do not use the default npm global prefix on LUNARC; keep global tools under
`/projects/hep/fs10/shared/codex-tooling/npm-global` so compute nodes and
login shells use the same versions.

## Importing existing auth from another machine

If you already have a working `codex login` somewhere else (e.g. your laptop),
you can copy the auth file directly instead of running `codex login` again:

```bash
# From the machine where codex is already authenticated:
rsync -av ~/.codex/auth.json ~/.codex/.credentials.json ~/.codex/config.toml \
  lunarc:/projects/hep/fs10/shared/codex-tooling/per-user/$USER/codex-home/

# Then on LUNARC, lock down the permissions:
ssh lunarc 'chmod 700 /projects/hep/fs10/shared/codex-tooling/per-user/$USER /projects/hep/fs10/shared/codex-tooling/per-user/$USER/codex-home && \
  chmod 600 /projects/hep/fs10/shared/codex-tooling/per-user/$USER/codex-home/*'
```

## Allocation lifecycle

- `hep` partition: max 5 days, idle pool of 12 nodes
- `lu48` partition: max 7 days, larger pool but more contention
- `gpua40` / `gpua100`: GPU partitions, max 1-7 days depending on flavor

To extend beyond a single allocation's lifetime, submit a new sbatch before
the current one expires (no built-in renewal). The supervisor session state
in `per-user/$USER/run/` persists across allocations, so you can re-attach
to the same lane assignments.

## Multi-host operation alongside the local Mac

The supervisor `~/.config/csup/hosts.toml` already has entries for `mac-mini`
and `laptop`. Adding a `lunarc` host lets `csup status <project>` aggregate
across hosts.

Before assigning source-writing work to LUNARC, apply
`docs/distributed-protocol.md`: the LUNARC `project_dir` must be a registered
execution mirror or registered Git worktree, its role must be explicit in
`.codex-supervisor.toml`, and source changes must move by Git branch/patch/PR.
Do not keep a mystery second copy of the same source tree on LUNARC, and do not
rsync edited source back and forth between local and remote hosts.

A minimal LUNARC entry:

```toml
[hosts."lunarc"]
ssh = "lunarc"  # uses your ~/.ssh/config alias
reachable = "ssh -o ConnectTimeout=3 -o BatchMode=yes lunarc true"
hostname_match = "cx"
description = "LUNARC SLURM compute allocation for remote codex-supervisor panes"
scheduler = "slurm"
slurm_job_name = "mcaccel-sup"
slurm_partition = "hep"
slurm_account = "hep2023-1-3"
slurm_time = "5-00:00:00"
slurm_nodes = "1"
slurm_cpus = "40"
slurm_mem = "200G"
slurm_slots = "2"       # station may book csup job names: mcaccel-sup, mcaccel-sup-2
slurm_max_panes = "24"  # conservative pane capacity per allocation
slurm_start_batch_size = "32"  # supervisor starts per persistent srun step
slurm_start_stagger_secs = "2" # delay between starts inside a batch
slurm_workdir = "/projects/hep/fs10/shared/nnbar/billy/mcaccel-supervisor"
slurm_output = "/projects/hep/fs10/shared/nnbar/billy/mcaccel-supervisor/holder.%j.log"
remote_env = "source /projects/hep/fs10/shared/codex-tooling/env-shared.sh"
supervisor = "/projects/hep/fs10/shared/codex-tooling/supervisor/codex-supervisor.sh"
```

For a project that should run on LUNARC, add a host stanza to that project's
`.codex-supervisor.toml` and point `project_dir` at the remote project path:

```toml
[hosts."lunarc"]
project_dir = "/projects/hep/fs10/shared/nnbar/billy/<project>"
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "<project>-lunarc"
role = "remote-executor"
sync_policy = "git-only"
```

`csup start <project> --host=lunarc` now checks for a running SLURM holder
allocation named `slurm_job_name`. If none is running, it submits one using
the host's `slurm_*` fields, waits for it to become RUNNING, and starts the
supervisor through a persistent `srun --overlap` step. The persistent step is
important: a short `srun` that exits immediately can let SLURM reap the tmux
server and worker panes.

The local `http://127.0.0.1:7777` dashboard reads the same host/project config.
For `scheduler="slurm"` hosts it probes the active job ID through `ssh lunarc`
and captures panes via `srun --jobid=<jobid> --overlap tmux ...`, so LUNARC
sessions appear on the same localhost dashboard as laptop/Mac sessions. A
separate `ssh -L 7778:<node>:7780` tunnel is still useful for debugging a
dashboard running wholly on the compute node, but is no longer required for
the local aggregate view.

## Station-managed requests

AI sessions should not pick LUNARC nodes themselves. They should ask the
station for capacity:

```bash
csup factory-run <project> --host=lunarc --scenario=resume --dry-run
csup factory-run <project> --host=lunarc --scenario=resume --apply
csup station <project> --host=lunarc --sessions=1 --workers=4 --dry-run
csup station <project> --host=lunarc --sessions=1 --workers=4 --apply
```

Prefer `factory-run` when resuming an AI factory from queues: it counts queued
`/goal` work, refuses no-work launches, selects a conservative worker/session
budget, then delegates to `station`. Use raw `station` only when the operator
already knows the exact session and worker counts.

`station` first uses running holder allocations when they have enough free pane
room. If the current allocation is full, it submits the next configured slot
(`slurm_job_name-2`, `slurm_job_name-3`, up to `slurm_slots`). If the new holder
job remains queued after `CSUP_SLURM_WAIT_SECS`, it reports a `HOLD` with
`reason=slurm_queue` and starts no workers. This is intentional: the login node
is only a scheduler/control endpoint, never a Codex compute target. Per-project
LUNARC usage is capped at two computer nodes by default. Use `slurm_max_panes`,
`CODEX_SUPERVISOR_MAX_LOAD_PER_CPU`, and queue depth to pack safe pane counts
onto those two allocations; do not create a third holder for the same project.

For high-density runs, `station` batches supervisor starts on each running
allocation. A request for many sessions can therefore use one persistent
`srun --overlap` launcher per batch instead of one `srun` job step per session,
which reduces SLURM step/fork pressure when the total pane count is above 100.
Use host `slurm_start_batch_size` or env `CSUP_STATION_START_BATCH_SIZE` to
lower the batch size if the launch command becomes too large; the default is 32
sessions per persistent step. Starts inside each batch are serialized with a
small delay (`slurm_start_stagger_secs` or `CSUP_STATION_START_STAGGER_SECS`,
default 2 seconds) to avoid creating a second fork storm inside the compute
allocation.

LUNARC login-node safety is fail-closed. LUNARC host stanzas must set
`scheduler = "slurm"`; otherwise `csup start` refuses to run. Every persistent
launcher also checks that `SLURM_JOB_ID` is present inside the `srun` payload
before starting tmux/Codex. If no allocation is running and the scheduler keeps
the holder queued, `station` reports `HOLD` rather than spawning on the login
node.

## Isolation policy

LUNARC's codex sessions inherit the same isolation rules as local sessions.
For the nnbar-simulation project specifically: the LUNARC supervisor handles
G4GPU / MCAccel R&D work only. The thesis-critical NNBAR production pipeline
runs vanilla Geant4 on its own SLURM jobs, never inside the codex supervisor.
See `docs/policies/g4gpu-isolation.md` in nnbar-simulation for the full rule.

## Troubleshooting

- **`Disk quota exceeded` writing to `$HOME`**: home filesystem on LUNARC has
  a small per-user quota. The shared toolchain redirects every config
  (`NPM_CONFIG_USERCONFIG`, `NPM_CONFIG_CACHE`, `CODEX_HOME`, supervisor run
  dir) to `/projects/.../codex-tooling/...`. If a command still writes to
  `$HOME`, find the env var responsible and add it to `env-shared.sh`.
- **`nvm is not compatible with the "NPM_CONFIG_PREFIX" environment variable`**:
  don't export `NPM_CONFIG_PREFIX` — nvm manages prefix itself. For
  `npm install -g`, use the `--prefix=$TOOLS/npm-global` flag instead.
- **Compute node refuses direct SSH (`Connection closed`)**: this is expected.
  Use `srun --jobid=<jobid> --overlap` to attach to an existing allocation.
- **Dashboard at `http://localhost:7777` doesn't show LUNARC sessions**: run
  `csup hosts` and confirm `lunarc` shows `up job=<jobid>`. Then confirm the
  relevant project has a `[hosts."lunarc"]` section locally. If the job is up
  but no panes appear, check that the supervisor was started through the
  persistent `csup start ... --host=lunarc` path rather than a short-lived
  manual `srun` step.
