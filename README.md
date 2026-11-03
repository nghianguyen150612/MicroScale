# MicroScale

**Tailscale, built smaller.** Independent build and packaging pipeline for embedded Linux.

MicroScale builds upstream Tailscale without vendoring or forking its source. It is not an official Tailscale product.

## Three compression profiles

| Profile | Upstream build flags | Extra packing | Intended status |
| --- | --- | --- | --- |
| **Safe** | `--box --strip` | None | Preferred baseline |
| **Small** | `--box --extra-small` | None | Feature-reduced; needs device qualification |
| **Extreme** | `--box --extra-small` | UPX `--best --lzma` | Experimental; not an automatic deployment target |

All three combine the `tailscale` CLI and `tailscaled` daemon in one executable, dispatched by executable name. The release archive contains one binary and two symlinks. The build uses `CGO_ENABLED=0`, `GOOS=linux`, and `GOARCH=arm64` by default.

**Upstream pin:** `VERSION` is `v1.104.4`; `UPSTREAM_COMMIT` locks the exact source commit. Updating the version requires changing both files, then running CI again.

## Build locally

Requires Git, a Go toolchain compatible with the pinned upstream `go.mod`, and the Tailscale source. The Extreme profile additionally requires UPX. The verification script requires `file`, `timeout`, and QEMU for non-native ARM64 execution.

```sh
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
git clone --depth 1 --branch "$(cat VERSION)" https://github.com/tailscale/tailscale.git upstream
test "$(git -C upstream rev-parse HEAD)" = "$(cat UPSTREAM_COMMIT)"
sh tests/test_scripts.sh
GOARCH=arm64 sh scripts/build.sh safe "$PWD/upstream" "$PWD/dist"
GOARCH=arm64 sh scripts/build.sh small "$PWD/upstream" "$PWD/dist"
GOARCH=arm64 sh scripts/build.sh extreme "$PWD/upstream" "$PWD/dist"
sh scripts/verify.sh safe arm64 "$PWD/dist"
```

The output is `dist/microscale-{safe,small,extreme}-linux-arm64.tar.gz`, with SHA256 sidecars. `dist/<profile>/metrics.tsv` records raw executable bytes before and after UPX. Use GitHub Actions to build and smoke-test all three profiles independently.

## Safety and qualification

- **No automatic router installation.** Do not replace a live VPN binary without a local LAN management path, backup, and tested rollback.
- Small/Extreme use upstream's reduced feature set. In particular, do **not** assume login, `tailscale up`, Exit Node, Subnet Router, Tailscale SSH, or reconnect works until tested on the target router.
- UPX changes executable memory behavior and can weaken security properties. Extreme is **experimental**, even if its CLI smoke test passes.
- Check `uname -m` and userspace compatibility on the router before deployment.
- Compressed archive size and ELF size are **not** equal to NAND space reclaimed on compressed UBIFS.
- The first CI build may fail if upstream toolchain/features or UPX are incompatible; failures must be fixed rather than bypassed.

## Licensing

MicroScale is independently maintained. Upstream Tailscale source and any redistributed executable remain subject to the upstream license and required notices: https://github.com/tailscale/tailscale . Preserve applicable notices in downstream releases.
