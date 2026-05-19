#!/usr/bin/env bash
#
# Build an OpenWrt 25.12.x image for the AVM FRITZ!Box 3390 that:
#   - includes 802.11p / ITS-G5 kernel patches (mac80211, ath9k, wireless-regdb)
#   - ships the otm-bridge MQTT publisher
#   - is preconfigured for first-boot use as an opentrafficmap.org receiver
#     (lan1 = WAN/DHCP, hostname = opentrafficmap, SSH allowed on WAN)
#
# Re-runnable — applies patches idempotently and skips already-completed steps.

set -euo pipefail

OWRT_REPO="${OWRT_REPO:-https://github.com/openwrt/openwrt.git}"
OWRT_BRANCH="${OWRT_BRANCH:-openwrt-25.12}"
OWRT_TAG="${OWRT_TAG:-v25.12.4}"
OTM_BRIDGE_FEED="${OTM_BRIDGE_FEED:-https://github.com/MPW1412/openwrt-otm-bridge.git}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWRT_DIR="$HERE/openwrt"

log()  { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn ]\033[0m %s\n' "$*" >&2; }

# --- 1. Clone OpenWrt at the pinned tag -------------------------------------

if [ ! -d "$OWRT_DIR/.git" ]; then
	log "cloning OpenWrt ($OWRT_BRANCH → $OWRT_TAG)"
	git clone --branch "$OWRT_BRANCH" --depth 1 "$OWRT_REPO" "$OWRT_DIR"
	(cd "$OWRT_DIR" && git fetch --depth 1 origin tag "$OWRT_TAG" && git checkout "$OWRT_TAG")
else
	log "OpenWrt tree already present at $OWRT_DIR"
fi

# --- 2. Install V2X kernel patches ------------------------------------------

install_patch() {
	local src="$1" dst="$2"
	mkdir -p "$dst"
	cp -v "$src" "$dst/"
}

log "installing V2X / regdb patches"
install_patch "$HERE/patches/mac80211/ath9k/600-ath9k_allow_11p.patch" \
	"$OWRT_DIR/package/kernel/mac80211/patches/ath9k"
install_patch "$HERE/patches/mac80211/ath/450-ath_regd_extend_5925.patch" \
	"$OWRT_DIR/package/kernel/mac80211/patches/ath"
install_patch "$HERE/patches/mac80211/subsys/950-mac80211_skip_qos_classifier_for_ocb.patch" \
	"$OWRT_DIR/package/kernel/mac80211/patches/subsys"
install_patch "$HERE/patches/wireless-regdb/600-regdb-ITS.patch" \
	"$OWRT_DIR/package/firmware/wireless-regdb/patches"

# --- 3. Add otm-bridge feed --------------------------------------------------

FEEDS_CONF="$OWRT_DIR/feeds.conf.default"
if ! grep -q '^src-git otm-bridge ' "$FEEDS_CONF"; then
	log "adding otm-bridge feed"
	echo "src-git otm-bridge $OTM_BRIDGE_FEED" >> "$FEEDS_CONF"
fi

cd "$OWRT_DIR"
log "feeds update + install"
./scripts/feeds update -a
./scripts/feeds install -a

# --- 4. Seed .config and resolve dependencies -------------------------------

log "seeding .config from $HERE/config/config.seed"
cp "$HERE/config/config.seed" "$OWRT_DIR/.config"
make defconfig

# --- 5. Build ----------------------------------------------------------------

JOBS="${JOBS:-$(nproc)}"
log "make download -j$JOBS"
make download -j"$JOBS"

log "make -j$JOBS V=s (this takes a while; logged to ../build.log)"
make -j"$JOBS" V=s 2>&1 | tee "$HERE/build.log"

# --- 6. Report --------------------------------------------------------------

IMG_DIR="$OWRT_DIR/bin/targets/lantiq/xrx200"
log "build done; artefacts under $IMG_DIR"
ls -la "$IMG_DIR"/*.bin "$IMG_DIR"/*.manifest 2>/dev/null || true
echo
log "flash with: ssh root@<box> sysupgrade -v /tmp/<image>-sysupgrade.bin"
