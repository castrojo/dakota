# CONTRIBUTING 

Thanks for helping out! 

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for contribution information.

This repository is for building the images, you are probably looking for [@projectbluefin/common](https://github.com/projectbluefin/common) to change something in Bluefin. Make sure you check [the architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture). 

## Local BuildStream Configuration

### Scheduler Tuning: builders × max-jobs ≈ nproc

BuildStream has two independent parallelism knobs that compound:

| Setting | What it controls | Default |
|---|---|---|
| `scheduler.builders` | simultaneous element build sandboxes | 4 |
| `build.max-jobs` | parallel compile jobs *within* each sandbox | 0 (= nproc) |

**The trap:** `builders: 32` with `max-jobs: 0` (auto) on a 32-core machine → **32 × 32 = 1,024 competing processes**. This causes severe CPU thrashing on source builds (WebKitGTK, gstreamer-plugins-rs, LLVM).

**The rule:** `builders × max-jobs ≈ nproc`

| Machine | builders | max-jobs | result |
|---|---|---|---|
| 32-core (ghost) | 16 | 2 | 32 concurrent jobs |
| 16-core | 8 | 2 | 16 concurrent jobs |
| 8-core laptop | 4 | 2 | 8 concurrent jobs |

Note: `fetchers` is independent (I/O-bound, not CPU-bound) — keep it high (16–32) to saturate the two remote CAS endpoints (`gbm.gnome.org`, `cache.projectbluefin.io`).

Most builds pull nearly everything from the remote CAS and never hit these limits. This tuning only matters when building elements from source (e.g., after a junction update causes widespread cache misses).

## BST Cache Configuration

BuildStream's local artifact cache grows unbounded by default. On machines with limited disk space, add `~/.config/buildstream/userconfig.yaml`:

```yaml
scheduler:
  builders: 16      # builders × max-jobs ≈ nproc (prevents CPU thrashing)
  fetchers: 32      # high: two fast remote CAS endpoints
  pushers: 8
  network-retries: 5

build:
  max-jobs: 2       # per-element parallelism; builders × max-jobs ≈ nproc

cache:
  quota: 150G            # auto-GC when cache exceeds this size
  reserved-disk-space: 10%
  low-watermark: 70%
  cache-buildtrees: never  # don't store intermediate build trees locally
```

Run `just gc` to trigger cache cleanup manually.
