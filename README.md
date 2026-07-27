# Mega Drive for Analogue Pocket

[![Latest Release](https://img.shields.io/github/v/tag/drizzt/openFPGA-MegaDrive?label=latest)](https://github.com/drizzt/openFPGA-MegaDrive/releases/latest) [![Downloads](https://img.shields.io/github/downloads/drizzt/openFPGA-MegaDrive/total)](https://github.com/drizzt/openFPGA-MegaDrive/releases) [![Platform](https://img.shields.io/badge/platform-Analogue%20Pocket-blue)](https://openfpga-library.github.io/analogue-pocket/)

LLM assisted port of [Nuked-MD-FPGA](https://github.com/nukeykt/Nuked-MD-FPGA),
via [MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer). The
console is a gate-level model of the real silicon, not a behavioural rewrite.

## Status: early, playable, audio broken

Sonic the Hedgehog boots and plays stably on a real Pocket, but this is not a
finished core:

- **Audio is noisy.** Known open issue. Gameplay is unaffected.
- **Timing does not close.** The build ships about 1.9 ns slow, so anything
  beyond Sonic 1 may misbehave.
- Only plain linear ROMs, NTSC only, no saves.

Bugs here are likely port-specific. Please do not report them to the MiSTer or
Nuked-MD repositories.

## Features

- **Mega Drive / Genesis** cartridges up to 4 MB (`.md`, `.bin`, `.gen`)
- **6-button pad** mapped to the Pocket's face buttons and triggers
- **FM and PSG audio** straight out of the gate-level sound chips (currently
  noisy, see above)
- **Settings**: PAL Timing, Japanese Machine, and Reset Core

## Not included

- **MD+ and CDDA**, which need hardware the Pocket does not have
- **Master System backward compatibility**
- **SVP** (Virtua Racing)
- **All cart mappers and special chips**: SSF2, Pier Solar, EEPROM carts,
  J-Cart, Realtec, Sega Channel, and per-game quirks
- **Battery saves**, so cartridge saves are lost on power off
- **Cheat engine**, **multitaps**, **lightgun**, **keyboard**, and **mouse**
- **Savestates and sleep**, so leaving the core loses your progress

## Known deviations

- NTSC only. **PAL Timing** changes the VDP's line and field counts but not the
  master clock, so PAL runs at the wrong rate.
- The dot clock is fixed at H40, so H32 (256 pixel) modes come out
  geometrically wrong.
- No region auto-detection and no audio filtering.

## Controls

| Pocket | Mega Drive |
|---|---|
| D-pad | D-pad |
| B | B |
| A | C |
| Y | A |
| X | Y |
| L | X |
| R | Z |
| Start | Start |
| Select | Mode |

A Mega Drive pad has no reset button, so use "Reset Core" in the Core Settings
menu.

## Installation

1. Download the [latest release](https://github.com/drizzt/openFPGA-MegaDrive/releases/latest)
   zip (`openfpga-MegaDrive_*.zip`).
2. Copy the `Cores/`, `Platforms/`, and `Assets/` folders from the zip to the
   root of your SD card.
   - **macOS users:** Finder replaces folders instead of merging them, so copy
     the contents manually and be careful.
3. Place your ROMs in `Assets/genesis/common`.

Platform artwork is not bundled. If your SD card does not already have images
for this platform, grab them from
[dyreschlock/pocket-platform-images](https://github.com/dyreschlock/pocket-platform-images).

## Building

Needs Quartus Prime 21.1, local or via the `raetro/quartus:21.1` container
image. That is what CI builds and releases with.

```bash
scripts/build.sh
```

`scripts/build.sh` uses a local Quartus when it finds one and falls back to the
container image in `QUARTUS_IMAGE` otherwise. Set `CONTAINER_RUNTIME=podman` if
that is your runtime.

`rtl/upstream/` tracks MegaDrive_MiSTer. Copybara mirrors upstream onto the
`vendor/upstream` branch, opens a pull request merging it here, and arms
auto-merge; git's three-way merge is what carries the port's edits across a sync,
so those files are edited in place like any other. The cycle is unattended and
lands a release by itself. It stops for a human on a merge conflict or a red
timing gate, and on nothing else.

Three repo settings hold it up, all one-time:

- **Allow auto-merge** on, and at least one required status check on `master`
  (`gate`). Without a required check there is nothing for auto-merge to wait on.
- **Squash** and **rebase** merging off. Either one drops the merge parent, and
  the next sync then replays all of upstream against a tree that already has it.
- **Automatically delete head branches** off. Deleting `vendor/upstream` destroys
  the merge base and Copybara's baseline.

Everything this port changes on top of upstream is

```bash
git diff origin/vendor/upstream master -- rtl/upstream
```

## Credits

- **[Nuked-MD-FPGA](https://github.com/nukeykt/Nuked-MD-FPGA)**: nukeykt's
  gate-level Mega Drive model, the console itself
- **[MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer)**:
  the MiSTer wrapper this port was cut from, by its contributors
- **APF framework**: Analogue (see file headers)
- **[agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)**:
  data loader/unloader and audio I2S modules (MIT)
- **[drizzt/openfpga-SMS](https://github.com/drizzt/openfpga-SMS)**: sibling
  port this repository's tooling and layout come from

## License

GPLv3 (see LICENSE); individual files keep their original licenses as noted in
their headers. Nuked-MD-FPGA is GPLv2-or-later, see
`rtl/upstream/nuked-md/LICENSE`.
