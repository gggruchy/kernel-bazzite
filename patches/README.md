# Custom Kernel Patches

## Structure
- `cachy/`     — CachyOS scheduler and performance patches
- `amd/`       — AMD-specific optimizations
- `memory/`    — Memory management improvements (le9uo, zram, etc.)
- `security/`  — Mitigation tuning
- `misc/`      — Other patches

## Applied as
Numbered patches in kernel.spec: patch-5-cachy.patch, patch-6-amd.patch, etc.
Combined via: scripts/combine-patches.sh
