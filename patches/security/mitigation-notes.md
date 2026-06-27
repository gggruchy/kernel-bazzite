# Spectre/Meltdown Mitigation Decisions — Ryzen Z1 Extreme (Zen 4)

## Not affected (zero cost already)
- meltdown, l1tf, mds, tsx_async_abort, srbds, mmio_stale_data
- gather_data_sampling, ghostwrite, indirect_target_selection
- itlb_multihit, reg_file_data_sampling, retbleed
→ No action needed. Kernel already skips these on AMD.

## Active mitigations — KEEP (KVM VMs present)
- spec_rstack_overflow (Safe RET) — Zen 4 RAS attack, low overhead, keep
- spec_store_bypass (SSBD via prctl) — already optimal, apps opt-in only
- vmscape (IBPB before userspace exit) — VM escape vector, non-negotiable

## Active mitigation — TUNE
- spectre_v2: currently "STIBP always-on" → change to "STIBP conditional"
  Saves IPI overhead on every context switch when not needed.

## Recommended cmdline additions to /etc/kernel/cmdline or grub:
  spectre_v2=eibrs stibp=conditional

## NOT recommended (would break VM isolation):
  mitigations=off   ← disables IBPB/IBRS, allows VM→host spectre attacks
  nospectre_v2      ← same risk
