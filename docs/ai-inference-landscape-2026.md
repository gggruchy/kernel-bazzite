# AI Inference on AMD RDNA3 APU (gfx1103 / Z1 Extreme) — 2026 Landscape

**Hardware:** AMD Ryzen Z1 Extreme — Phoenix die, RDNA3 iGPU (gfx1103 / Radeon 780M),
24 GB unified LPDDR5 RAM, no NPU (fused off on handheld SKU), no Infinity Cache (iGPU only).

---

## 1. Backend Decision: Vulkan is the correct primary path

| Backend | Status on gfx1103 | Notes |
|---|---|---|
| **Vulkan (RADV)** | Working, recommended | Sees full GTT pool; actively optimized |
| **ROCm/HIP** | Working (Fedora 44) | Fedora 44 rocBLAS 7.1 includes `Kernels.so-000-gfx1103.hsaco` — TensileLibrary crash fixed |
| **ROCm Flash Attention** | Not available | rocWMMA rejects gfx1103 at compile time (static assertion). Must build with `GGML_HIP_ROCWMMA_FATTN=OFF` |
| **CPU (BLAS)** | Fallback | Bandwidth-limited by DDR5; use when model doesn't fit GPU |

**ROCm on Fedora 44:** Install `rocm-hip rocblas hipblas rocm-device-libs rocm-comgr rocm-hip-devel rocblas-devel hipblas-devel` via rpm-ostree. Fedora 44's rocBLAS package includes `Kernels.so-000-gfx1103.hsaco` — the TensileLibrary crash is resolved without any workaround.

**Required env var:** `HSA_OVERRIDE_GFX_VERSION=11.0.3` — tells ROCm to use correct kernels for gfx1103.

**rocWMMA exclusion:** rocWMMA supports gfx908/90a/940/941/942 (CDNA) and gfx1100/1101/1102 (discrete RDNA3) only. gfx1103 iGPU is explicitly rejected by a static assertion in config.hpp. Build llama.cpp HIP with `-DGGML_HIP_ROCWMMA_FATTN=OFF`.

---

## 2. Memory Architecture — the most important lever

The iGPU shares system RAM. Two pools:
- **BIOS VRAM (vis_vram):** Static carveout, typically 512 MB–8 GB depending on BIOS setting
- **GTT (Graphics Translation Table):** Dynamic, mapped from system RAM on demand

By default the kernel caps GTT around 3× BIOS VRAM — catastrophically small for LLM weights.

**What Vulkan sees by default on this system:** ~11.8 GB (GTT + vis_vram combined).

**Fix:** Override via `amdgpu.gttsize` modprobe parameter:
```
# /etc/modprobe.d/amdgpu-gtt.conf
options amdgpu gttsize=20480
```
Takes effect on reboot. After this, Vulkan sees ~20 GB, enabling 35B Q4_K_M models (~20 GB) to
load entirely on GPU rather than CPU-offloading layers.

**Expected inference speedup from full-GPU vs split load:** 2–4× on token generation.
Prompt processing (prefill) improvement: moderate (~15%). CPU-offloaded layers are bandwidth-limited
by DDR5 (~70 GB/s effective) vs GPU internal bandwidth (RDNA3 iGPU: ~100+ GB/s).

**ROCm note:** ROCm does not use GTT — it only sees BIOS VRAM. This is an additional reason
Vulkan outperforms ROCm on APUs: Vulkan has access to the full memory pool.

---

## 3. Known-Good Environment Variables and Build Flags

### RADV Vulkan driver
```bash
RADV_PERFTEST=nogttspill   # Prevents GPU→GTT spill; significant perf improvement on iGPUs
```
Apply at launch: `RADV_PERFTEST=nogttspill ./llama-cli ...`
Or permanently in `/etc/environment` or a wrapper script.

### Cooperative matrix (coopmat)
gfx1103 supports `VK_KHR_cooperative_matrix` via RADV. Enables hardware matrix acceleration
in llama.cpp's Vulkan shaders. Verify support:
```bash
vulkaninfo | grep cooperativeMatrix
```
Build llama.cpp with coopmat enabled (default in recent builds when detected).

### llama.cpp build
```bash
cmake -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release -S . -B build
```
Standard release build. coopmat is auto-detected from Vulkan caps.

### Recommended context/batch params (780M tier)
```
-b 2048 -c 8192
```
Larger context increases KV cache pressure on the unified memory pool.

---

## 4. RADV/Mesa Patches Relevant to Inference

### "CU mode when LDS is used" — Valve/Rhys Perry, merged Mesa 25.3 (Oct 2025)
- **What:** Three patches changing how RADV schedules compute units when Local Data Share
  (LDS) memory is in use — which is exactly the access pattern of LLM matrix kernels.
- **Gain:** 13% improvement in prompt processing (pp512): 3586 → 4046 tok/s on 7B Q4 benchmark.
- **Applies to:** All RDNA architecture including gfx1103. Requires Mesa ≥25.3.
- Check Mesa version: `vulkaninfo | grep driverVersion`

### Wave32 Flash Attention (llama.cpp PR #19625)
- Enables Wave32 execution mode for flash attention on RDNA3. Significant throughput improvement.
- Check if your llama.cpp build includes this: `git log --oneline | grep -i wave32`

---

## 5. Kernel-Level Optimizations Applied to This System

### GTT expansion (applied)
```
/etc/modprobe.d/amdgpu-gtt.conf: options amdgpu gttsize=20480
```

### Transparent Huge Pages = always (applied, next boot)
- Reduces TLB pressure during KV cache and weight tensor allocation.
- Set via kernel arg: `transparent_hugepage=always`
- Live: `echo always > /sys/kernel/mm/transparent_hugepage/enabled`

### NUMA balancing disabled (applied)
- Single-node die; no cross-NUMA migration to perform. Pure overhead.
- Kernel arg: `numa_balancing=disable`

### vfs_cache_pressure=200 (applied)
- More aggressive inode/dentry cache reclaim; frees more RAM for inference.
- `/etc/sysctl.d/99-ggr-memory.conf`

### dmemcg VRAM priority patches (NOT applied — low APU benefit)
- Valve/pixelcluster patches (v6) fix VRAM eviction for discrete GPUs.
- Not in kernel-bazzite yet (issue #52 open as of 2026-06-27).
- APU impact: "unknown/limited" per patch author — iGPU uses system RAM throughout,
  so the discrete-VRAM vs GTT distinction doesn't apply the same way.

---

## 6. What Doesn't Apply to This Hardware

| Thing | Why it doesn't apply |
|---|---|
| **Infinity Cache** | Only on discrete RDNA3 (RX 7000 series). iGPU has none. |
| **AITER Unified Attention** | AMD's attention library for MI300 Instinct cards + vLLM. Not for consumer APUs. |
| **hipEngine** | Targets gfx1100 (RX 7900 XTX) and gfx1151 (Strix Halo). gfx1103 not listed. |
| **vLLM + Flash Attention 2 Docker** | Depends on ROCm; ROCm broken on gfx1103 for GEMM. |
| **ROCm 7.2.4 patches** | MI300 Instinct server cards only. |
| **NPU / amdxdna** | Z1 Extreme NPU is fused off. No /dev/accel. |

---

## 7. Models and Expected Performance on This System (Post-GTT Expansion)

| Model | Size | Fits GPU? | Expected gen tok/s |
|---|---|---|---|
| Qwen3.6-27B IQ2_M | ~8–9 GB | Yes (pre-GTT too) | ~18–25 tok/s |
| Qwen3.6-35B-A3B Q4_K_M | ~20 GB | Yes (post-GTT) | ~10–18 tok/s (estimate) |
| Huihui-35B Q4_K | ~20 GB | Yes (post-GTT) | ~10–18 tok/s (estimate) |

MoE (Mixture of Experts) models like Qwen3.6-35B-A3B are favorable on this hardware because
only active expert parameters are loaded per token — actual compute per token is ~3B parameter
equivalent despite 35B total weights.

---

## 8. Pending Validation (Requires Reboot)

After next reboot:
1. Verify GTT expanded: `cat /sys/class/drm/card1/device/mem_info_gtt_total | numfmt --to=iec`
2. Confirm llama.cpp Vulkan sees ~20 GB: `llama-cli --list-devices`
3. Run 35B model — confirm full GPU load (no CPU offload layers): `llama-cli -m model.gguf -ngl 999 ...`
4. Benchmark: `llama-bench -m model.gguf -ngl 999`

---

## 9. Distributed Inference — RPC Split Across Two Machines

For models that exceed a single machine's GTT pool, llama.cpp's RPC backend enables GPU layer distribution.

**Setup (2026-06-27):**
- **Local (CSE-GC-R-PW1):** 20 GB Vulkan pool — primary GPU, runs master process
- **Remote (192.168.2.165):** ~10 GB Vulkan pool (post-reboot with gttsize=10240) — RPC backend
- **Combined:** ~30 GB — fits Qwen3.6-35B-A3B-UD-Q4_K_M (23 GB) entirely on GPU

**RPC server build:**
```bash
cmake -DGGML_VULKAN=ON -DGGML_RPC=ON -DCMAKE_BUILD_TYPE=Release -S . -B build
cmake --build build --target rpc-server
```

**Run RPC server (on 192.168.2.165):**
```bash
RADV_PERFTEST=nogttspill ~/llama.cpp/build/bin/rpc-server -H 0.0.0.0 -p 50052
```

**Run inference (on local, with RPC):**
```bash
RADV_PERFTEST=nogttspill ~/llama.cpp/build/bin/llama-cli \
  --rpc 192.168.2.165:50052 \
  -ngl 999 -m ~/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
```

**Note:** RPC transfers tensors over TCP — LAN bandwidth (GbE ~900 Mb/s) becomes a bottleneck for large models. 1 GbE vs the GPU's internal bandwidth ratio matters for layer-split inference throughput.

---

## 10. Open Questions / Next Research

- Does ROCm 7.1 work reliably for Qwen3.6 35B inference on gfx1103 with `HSA_OVERRIDE_GFX_VERSION=11.0.0`?
- Does the `ollama-rocm-gfx1103-ubuntu` approach (patching Fedora 43 Tensile kernels into rocBLAS)
  work on Bazzite? Repo: `github.com/johnsonfarmsus/ollama-rocm-gfx1103-ubuntu`
- Wave32 flash attention status in current llama.cpp build?
- Samehadaonsen's `vulkan_mul_mat_vec_4k` optimization — is it in current build?

---

*Last updated: 2026-06-27. Hardware: AMD Ryzen Z1 Extreme / Phoenix / gfx1103.*
*Maintained in `ggr-patches` branch of `gggruchy/kernel-bazzite`.*
