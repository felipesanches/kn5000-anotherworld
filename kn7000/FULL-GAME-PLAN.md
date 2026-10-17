# Another World on the KN7000 — the full game: assets, status, plan (2026-10-17)

The intro and the first stage (the lake, part 0x3E82) are verified pixel-identical to the
reference VM (rustyworld) and playable from the keybed, MIDI IN 1 and the panel. This page is the
starting point for the rest of the game: every asset is now on the card and resident, the VM can
enter every part, and each part's opening has been checked against the reference.

## 1. Assets: all 146 resources, resident at boot

| what        | how                                                                                                                                                                                                                                                                                                                                                                                         |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| source      | the original MS-DOS release, `~/compartilhado/MSDOS/` (`MEMLIST.BIN` + `BANK01..0D`) — the same files the reference reads (`AW_DATA` in the Makefile)                                                                                                                                                                                                                                       |
| unpacking   | `tools/aw_extract.py`: MEMLIST parser + ByteKiller unpacker, CRC checked; **146/146 byte-identical** to rustyworld's own unpacker (`dumpres`)                                                                                                                                                                                                                                               |
| layout      | every resource at a fixed address from `RES_BASE` = `0x44200000` (4-byte aligned, id order) to `0x443A6748`: 1,730,258 bytes. Generated tables `ResAddr`/`ResSize`/`ResType` (`build/res/awres_tab.s`)                                                                                                                                                                                      |
| on the card | that RAM image cut into **31 pack files** `C:\TECHNICS\DATA\AWPxx.AW` of <= 64 KB (the firmware's `fread` count is 16 bits)                                                                                                                                                                                                                                                                 |
| loading     | `LoadGameData` (hook, firmware task) reads the packs and copies each to its base: **10.6 s** from SD CARD LOAD to loaded (`awresverify.lua`). `probes/awloadtime.lua` + `_fit.py`: each file costs ~71 ms of fixed overhead and the data reads at ~255 KiB/s (34 files, 9.06 s of reading), so a one-file-per-resource card (140 files; tried, 19.3 s) spent most of its time opening files |
| verified    | `probes/awresverify.lua` + `.py`: **146/146 resources byte-exact in RAM** at the tabled addresses, no overlaps                                                                                                                                                                                                                                                                              |
| by type     | 103 sounds (699,868 B), 3 music modules (33,344 B), 12 screen bitmaps (384,000 B), 9 palettes, 9 bytecode, 9 video1, 1 shared video2                                                                                                                                                                                                                                                        |

The `0x44` window is mapped as 16 MB by the MAME driver; the game now uses it up to `0x444A1000`
(~4.6 MB: pages, VM state, resources, font and strings; plus the debug trace buffer at
`0x44800000`). The real instrument's size of this window is still unconfirmed.

## 2. The VM side

- `InitForPart` takes every part 0x3E80..0x3E89 from `PartTable` (the original engine's part list).
- Opcode 0x19 (LOAD): a part id is a deferred part switch; a **bitmap** resource is decoded into
  page 0 (four 8000-byte planes, plane k = pixel bit k — `LoadBitmap`); sounds and music are
  already resident, so nothing to do until audio exists.
- `copyPage` with a vertical scroll outside ±199 now skips the copy, as raw/rawgl do (the port
  used to clamp to 199; the final part scrolls past the range).

## 3. Each part's needs (`tools/aw_partinfo.py build/res --compact`)

| part | name       | pal/code/vid1/vid2 | code bytes | sound ids | music | bitmaps     | switches to                        | reads F4/DA |
|------|------------|--------------------|------------|-----------|-------|-------------|------------------------------------|-------------|
| 3E80 | protection | 14/15/16/-         | 4321       | 0         | -     | 12,13,47,53 | 3E81                               | -/-         |
| 3E81 | intro      | 17/18/19/-         | 9871       | 18        | 00,07 | -           | 3E82                               | F4/-        |
| 3E82 | water      | 1A/1B/1C/11        | 20810      | 21        | -     | -           | 3E80,3E81,3E83                     | -/-         |
| 3E83 | prison     | 1D/1E/1F/11        | 39695      | 25        | -     | 48,49       | 3E84                               | -/-         |
| 3E84 | city       | 20/21/22/11        | 62683      | 32        | -     | 43,44,45,46 | 3E85,3E86                          | -/-         |
| 3E85 | arena      | 23/24/25/-         | 8287       | 9         | -     | -           | 3E86                               | -/-         |
| 3E86 | baths      | 26/27/28/11        | 50736      | 24        | -     | 90,91       | 3E85,3E87                          | -/-         |
| 3E87 | final      | 29/2A/2B/11        | 2886       | 4         | 00,8A | -           | -                                  | -/-         |
| 3E88 | password   | 7D/7E/7F/-         | 4257       | 0         | -     | -           | 3E81,3E82,3E83,3E84,3E85,3E86,3E87 | -/DA        |

(0x3E89 is a second entry for the password screen, with the same resources.) All parts decode
with no invalid opcode; together they use 29 opcode kinds, all implemented. `F4` = reads the
music player's sync mark (var 0xF4); `DA` = reads the last typed character (var 0xDA). The full
sound and load lists: `python3 -I tools/aw_partinfo.py build/res`.

## 4. Status of every part against the reference

Each part entered directly (requested at the end of tick 0 in both VMs: `probes/awcksum.lua`
`AW_START_PART`, rustyworld `refcksum` `START_PART`), no input, CRC-32 of the displayed page per
tick (`probes/cksum_pages.py` + `compare_frames.py`), against the reference with the original
engine's part setup (`AW_NO_VIDEO2_BG=1`, section 6); `probes/awparts.sh` reruns all of it:

| part | name       | ticks compared | identical | notes                                                                                                                  |
|------|------------|----------------|-----------|------------------------------------------------------------------------------------------------------------------------|
| 3E80 | protection | 600            | 600       | static screen (2 distinct frames), waiting for input                                                                   |
| 3E81 | intro      | 2612           | 2612      | the whole intro, from boot (`CHECKSUM-COMPARISON.md`)                                                                  |
| 3E82 | water      | 600            | 600       | the lake opening; plus Felipe's played session 1176/1176                                                               |
| 3E83 | prison     | 600            | 600       | opening, no input                                                                                                      |
| 3E84 | city       | 600            | 600       | opening, no input                                                                                                      |
| 3E85 | arena      | 600            | 600       | opening, no input; also 600/600 against upstream                                                                       |
| 3E86 | baths      | 600            | 600       | includes the bitmaps 0x90 and 0x91 (LoadBitmap)                                                                        |
| 3E87 | final      | 600            | 600       | the final part's opening scroll; 599/600 against upstream rustyworld (tick 3: its video2-into-page-0 quirk, section 6) |
| 3E88 | password   | 600            | 600       | waiting for input (3 distinct frames)                                                                                  |
| 3E89 | password   | 600            | 600       | as 3E88                                                                                                                |

Frames past the opening depend on input (Lester stands still), so further coverage comes from
played sessions replayed into both VMs (`probes/awreplay.lua` + `replaycksum`), as for the lake.

## 5. What remains for the full game, in order

1. **Play through the parts, with the differential replay as the safety net.** Record sessions
   with `probes/awmonitor.lua` (keybed or `-midiin1`), replay them into both VMs, diff per tick.
   The part switches the bytecode can request (section 3) chain intro → lake → prison → city →
   arena/baths → final; the lake's normal exit is `LOAD 3E83` (bytecode 0x10CF). The game starts
   at the intro with the copy-protection bypass vars set in `GameReset` (0xBC=16, 0xC6=128,
   0xDC=33, 0xF2=4000 -- the same values the reference starts with).
2. **Password screen input (0x3E88/89).** It reads var 0xDA, the last typed character, so it needs
   a way to type letters; the current input map has only the D-pad and action. A note map or panel
   scheme for letters is a design choice to make. This also gives a way to jump to any part.
3. **Sound effects** (103 resources; opcode 0x18 PLAY_SOUND id/frequency/volume/channel). The
   format is 8-bit signed PCM after an 8-byte header (length and loop length in words), played
   on 4 channels at one of 40 frequencies (rustyworld `rodio.rs`). How the KN7000 can output raw
   PCM — through the tone generator or otherwise — is an open research question; the resources
   are resident, so only the player is missing.
4. **Music** (modules 0x07 intro, 0x8A final; 0x89 preloaded by the lake), the original's
   4-channel module player, instruments taken from the sound resources. The intro reads the
   music sync mark (var 0xF4): with the stub music it stays 0 in both VMs (hence the identical
   intro), so once music plays the intro's timing must be re-verified against a reference that
   produces marks.
5. **Pacing in the big parts.** City and baths have the largest code and polygon sets (62 KB and
   51 KB of bytecode, 65 KB of video1 each); measure each part's frame work time against
   `var[0xFF] × 20 ms` once they are played through.
6. **Real hardware.** Confirm the `0x44` window's size (the game needs ~4.6 MB of it) and the SD
   load time on the instrument.

## 6. Differences between the reference and the original engine (found here)

| where                           | rustyworld upstream                         | original engine (raw/rawgl), and the port | effect                                                                                                                                                                                              |
|---------------------------------|---------------------------------------------|-------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `setup_part` with a video2      | also decodes video2 into page 0 as a bitmap | copies only BITMAP resources to page 0    | video2 is 25,108 bytes, so the decode writes rows 0..27 of page 0; visible once, at tick 3 of the final part, where a scrolled copy leaves those rows. Every other part matches with and without it |
| `copy_page`, abs(vscroll) > 199 | `assert!` — panics (final part, tick 349)   | skips the copy                            | the reference now skips too                                                                                                                                                                         |

The reference changes are recorded in
`~/compartilhado/research-scratch/kn7000-aw-reference/replay-mods/rustyworld-kn7000-all.diff`.
