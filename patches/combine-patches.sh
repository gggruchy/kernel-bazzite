#!/usr/bin/env bash
# Combine individual patch files into numbered patch files for kernel.spec
# Run from repo root: bash patches/combine-patches.sh

set -e
cd "$(dirname "$0")/.."

# patch-5: CachyOS core (BORE + general improvements)
cat patches/cachy/cachy.patch \
    patches/cachy/bore.patch \
    patches/cachy/block.patch \
    patches/cachy/fixes.patch \
    > patch-5-cachy.patch
echo "patch-5-cachy.patch: $(wc -l < patch-5-cachy.patch) lines"

# patch-6: BBR3 TCP congestion control
cp patches/cachy/bbr3.patch patch-6-bbr3.patch
echo "patch-6-bbr3.patch: $(wc -l < patch-6-bbr3.patch) lines"

# patch-7: ASUS ROG handheld/device patches
cat patches/misc/asus.patch > patch-7-asus.patch
echo "patch-7-asus.patch: $(wc -l < patch-7-asus.patch) lines"

echo "Done. Add to kernel.spec:"
echo "  Patch5: patch-5-cachy.patch"
echo "  Patch6: patch-6-bbr3.patch"
echo "  Patch7: patch-7-asus.patch"
echo "  ApplyOptionalPatch patch-5-cachy.patch"
echo "  ApplyOptionalPatch patch-6-bbr3.patch"
echo "  ApplyOptionalPatch patch-7-asus.patch"
