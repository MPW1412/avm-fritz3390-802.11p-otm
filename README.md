# avm-fritz3390-802.11p-otm

Reproducible OpenWrt build for the **AVM FRITZ!Box 3390** that turns it
into a passive [opentrafficmap.org](https://opentrafficmap.org/) C-ITS / 802.11p
receiver — out of the box, no post-flash hand-configuration needed.

## What this is

Two small repos are involved:

1. **This one** — orchestrator. Holds the four kernel/regdb patches that
   make the AR9580 in the 3390 see and tune to the 5,9 GHz DSRC channels,
   plus a `build.sh` that pulls a fresh OpenWrt tree, applies the patches,
   adds the companion package as a feed, seeds `.config`, and runs the
   build.

2. **[`openwrt-otm-bridge`](https://github.com/MPW1412/openwrt-otm-bridge)**
   — the MQTT publisher that ships the daemon, the procd init (sniffer +
   bridge instances), and a `uci-defaults` script that applies the
   first-boot network/firewall/hostname setup.

Result: a `…-avm_fritz3390-squashfs-sysupgrade.bin` you flash, the box
reboots, on first boot it auto-configures `lan1` as DHCP-WAN, hostname
`opentrafficmap`, SSH-allowed-on-WAN, and starts publishing every captured
802.11(p) frame to `mqtts://cits1.opentrafficmap.org`.

## What the patches do

| Path | Effect |
| --- | --- |
| `patches/mac80211/ath9k/600-ath9k_allow_11p.patch` | Adds DSRC channels 170–185 (5850–5925 MHz) to `ath9k_5ghz_chantable`, bumps `ATH9K_NUM_CHANNELS` from 38 to 54. |
| `patches/mac80211/ath/450-ath_regd_extend_5925.patch` | Extends the ath common regulatory rules to cover up to 5925 MHz. |
| `patches/mac80211/subsys/950-mac80211_skip_qos_classifier_for_ocb.patch` | Skips the 802.1d/QoS-map override in `ieee80211_select_queue`, so `SO_PRIORITY` survives to EDCA classification. |
| `patches/wireless-regdb/600-regdb-ITS.patch` | Adds a `country DE: (5850 – 5925 @ 20), (33)` ITS-G5 rule. |

All four are forward-ports of the original
[`OpenWrt-V2X`](https://github.com/francescoraves483/OpenWrt-V2X) 21.02.1
patches by Florian Klingler and Gurjashan Singh Pannu (CCS Labs, Paderborn)
— author headers are preserved verbatim in each patch.

## How to build

```sh
git clone https://github.com/MPW1412/avm-fritz3390-802.11p-otm.git
cd avm-fritz3390-802.11p-otm
./build.sh
```

`build.sh` is idempotent — running again continues where it stopped, and
overwriting `OWRT_TAG=v25.12.5 ./build.sh` re-points the build at a newer
release without manual rebase work.

### Build host requirements

Tested on Manjaro/Arch with these packages installed:

```
base-devel git python ncurses zlib gawk unzip wget rsync quilt gettext
```

Other distros: see the [official OpenWrt build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem).

Expect ~25 GB free disk and 30–60 min on a modern multi-core box for the
first build (subsequent rebuilds with the same toolchain are much faster).

### Output

```
openwrt/bin/targets/lantiq/xrx200/openwrt-lantiq-xrx200-avm_fritz3390-squashfs-sysupgrade.bin
```

## How to flash

If the 3390 already runs stock OpenWrt 25.12.x:

```sh
scp -O openwrt/bin/targets/lantiq/xrx200/openwrt-*-avm_fritz3390-*-sysupgrade.bin \
    root@<box>:/tmp/
ssh root@<box> 'sha256sum /tmp/openwrt-*-sysupgrade.bin'   # verify against local sha256sum
ssh root@<box> 'sysupgrade -v /tmp/openwrt-*-sysupgrade.bin'
```

If the 3390 still runs AVM stock firmware, use the EVA bootloader on
`169.254.1.1` (FTP, login `adam2`/`adam2`) during the first ~10 s after
power-on — see the OpenWrt wiki for the canonical procedure.

## What you get on first boot

* `lan1` = **WAN**, DHCP + IPv6 RA
* `lan2`, `lan3`, `lan4` = `br-lan` with `192.168.1.1/24` (local admin)
* `Allow-SSH-WAN` firewall rule (port 22 reachable from the WAN side)
* hostname `opentrafficmap` → typically resolvable as `opentrafficmap.lan`
  via mDNS / your router's DHCP
* `mon0` = monitor on channel 178 (5890 MHz, 10 MHz width)
* WLAN-LED trigger `phy0rx` → LED blinks on every captured frame
* `tcpdump` rotating into `/tmp/mon0-YYYYMMDD-HHMMSS.pcapN` (5 × 1 MB ring)
* MQTT bridge live to `mqtts://cits1.opentrafficmap.org`, node-id =
  `phy0` MAC, ~65 s after boot

## Known limitations

* **No 2.4 GHz**, ever. The 3390's 2.4 GHz radio is on a second
  Atheros SoC (AR9342 "WASP") with its own RAM, no flash, only a MDIO +
  Ethernet bridge to the main Lantiq SoC. Mainline OpenWrt has never
  brought up that second SoC — the only working port is
  [andyboeh's 2020 fork](https://github.com/andyboeh/openwrt) which is
  unmaintained.
* **Receive-only.** OCB-mode TX could be enabled via `iw`, but
  transmitting on 5,9 GHz is reserved for ITS in Germany, so this build
  deliberately stays passive.
* **No on-device CAM/DENM decoding.** Raw frames are forwarded as-is to
  OTM's backend, which does the ASN.1 UPER parsing.

## Reproducibility / pinned versions

* OpenWrt: tag `v25.12.4` (override via `OWRT_TAG=…`)
* `mac80211`: backports-6.18.26 (as pinned by OpenWrt 25.12.4)
* Kernel: 6.12.x for the `lantiq/xrx200` target

## License

[WTFPL](http://www.wtfpl.net/) for the build orchestration and original
work in this repo. See `LICENSE` for the boring details about the
GPL-2.0-derived kernel patches under `patches/`.

## Credits

* [opentrafficmap.org](https://opentrafficmap.org/) for the public C-ITS
  ingest and the ESP32-C5 reference firmware that defined the wire format
  we mimic.
* [Francesco Raviglione](https://github.com/francescoraves483/OpenWrt-V2X)
  for the original V2X patches.
* [Florian Klingler](mailto:klingler@ccs-labs.org) and Gurjashan Singh
  Pannu (CCS Labs, Paderborn) as the original 11p-on-Linux patch authors.
* [HPI Potsdam 11p-on-linux project](https://gitlab.com/hpi-potsdam/osm/g5-on-linux/11p-on-linux)
  for the pointer that the 3390 hardware is fundamentally capable of this.
* [andyboeh](https://github.com/andyboeh) for getting OpenWrt onto the
  Lantiq side of the 3390 in the first place.
