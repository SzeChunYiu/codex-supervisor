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
├── npm-global/                755   shared — global npm packages, codex CLI
│   └── bin/codex
├── npm-cache/                 755   shared — npm download cache (read-mostly)
├── supervisor/                755   shared — codex-supervisor.sh + csup-dashboard
│   ├── codex-supervisor.sh
│   └── csup-dashboard
├── env-shared.sh              755   shared — one-liner any user sources
└── per-user/                  755   shared — parent of user-private dirs
    └── <username>/            700   user-private
        ├── codex-home/        700   credentials (auth.json, .credentials.json, config.toml)
        ├── .npmrc             600   per-user npm config
        └── run/               700   supervisor session state, sockets, logs
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
mkdir -p $USER_DIR/codex-home $USER_DIR/run

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
```

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

A minimal LUNARC entry:

```toml
[hosts."lunarc"]
ssh = "lunarc"  # uses your ~/.ssh/config alias
reachable = "ssh -o ConnectTimeout=3 -o BatchMode=yes lunarc true"
hostname_match = "cosmos1.int.lunarc"
description = "LUNARC compute cluster — submit via SLURM, codex toolchain at /projects/hep/fs10/shared/codex-tooling/"
```

Important: `csup` running on the Mac cannot directly `start` a supervisor on
a LUNARC compute node (the compute node only exists inside a SLURM allocation
identified by job ID). The supervisor on LUNARC is started manually inside an
`srun --overlap` shell using the procedure in "Running a supervisor session
on a compute node" above. Dashboard streaming via `ssh -L` then aggregates
LUNARC sessions into the local URL.

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
- **Dashboard at `http://localhost:7777` doesn't show LUNARC sessions**: the
  csup dashboard reads from a local state dir; LUNARC sessions live on the
  LUNARC filesystem. Either tunnel a second port (`localhost:7778`) or sync
  the LUNARC state dir into the local dashboard's watch path via rsync.
