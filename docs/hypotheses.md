# Mirax core — hypothesis log

This core is experimental. Every statement about the original CT805-3 board that has not been measured or traced is recorded here as a hypothesis. RTL files list the open hypotheses that affect them in their header (`Open hypotheses:`) and mark the exact lines with inline tags.

## Tag conventions

| Tag | Meaning |
|---|---|
| `[SRC:PCB <ref>]` | Taken from the board (silkscreen, component, traced connection), with the reference designator |
| `[SRC:DS]` | Taken from a component datasheet |
| `[SRC:MAME]` | Taken from MAME `misc/mirax.cpp`; reference only, not yet confirmed on the board |
| `[HYP H-nnn]` | Hypothesis whose origin is still to be recorded |
| `[HYP:AI H-nnn]` | Hypothesis proposed by the AI assistant |
| `[HYP:HUM H-nnn]` | Hypothesis proposed by the human author |
| `→ OK` / `→ KO` | Appended when the hypothesis is confirmed / rejected (the tag is kept) |
| `[DIFF:MAME]` | The board behaves differently from MAME; the board wins |
| `[CONF:HIGH/MEDIUM/LOW]` | Confidence level |
| `[VERIFY]` | Needs a measurement, a trace or a simulation check |

Lifecycle: when a hypothesis is closed, update the inline tag (`→ OK` / `→ KO`), fill in *Result* below, and remove the ID from the `Open hypotheses:` line of every affected file. A file with no open hypotheses can move from `UNDER VALIDATION` to `VALIDATED`.

Useful counts:

```sh
grep -rhoE "\[HYP:AI H-[0-9]+ → OK\]" rtl | sort -u | wc -l   # AI hypotheses confirmed
grep -rhoE "\[HYP:AI H-[0-9]+ → KO\]" rtl | sort -u | wc -l   # AI hypotheses rejected
```

## Hypotheses

| ID | Origin | Hypothesis | Evidence so far | How to close it | Files | Result |
|---|---|---|---|---|---|---|
| H-001 | TBD (CLK trace: AI) | Every clock is an integer division of the 12 MHz crystal; pixel clock = 12/2 = 6 MHz | Oscillator X1 + 74LS368 at M2 traced (CONF:MEDIUM). Common CLK net 74S161 B9 pin 2 ↔ 74LS161 B10 pin 2 traced on the solder side; it disappears into a via under B8 | Scope B9 pin 2; continuity from the B8 via to the divider flip-flop (L1 74LS107 or a nearby 74LS74) | mirax_clocks, mirax_video, mirax_pocket | open |
| H-002 | TBD | AY-3-8912 clock = 12/4 = 3 MHz | MAME value only | Scope AY pin (CLOCK) on R4/S4 | mirax_clocks, mirax_sound | open |
| H-003 | TBD | HTOTAL = 384, VTOTAL = 262 and the sync positions | MAME gives only 60 Hz and 256×256 | Scope HSYNC/VSYNC on the edge connector; measure line and frame periods | mirax_video | open |
| H-004 | TBD | The white potted "ORIGINAL SEAL" block is the main-CPU decryption module and is purely combinational | Decryption algorithm matches MAME and the ROM CRCs; the physical module is unexplored | Continuity from the module pins to the program EPROM address/data lines | mirax_main, mirax_decrypt | open |
| H-005 | TBD | Main decode uses 74LS138/139 + LS20/LS32 and matches the MAME map | MAME map only | Trace the chip-select lines of the RAMs and latches | mirax_main | open |
| H-006 | TBD | Sprite attribute b1[6] = flip X, b1[7] = flip Y | Marked "guess" in the code | Compare in-game sprite orientation against the real board / MAME | mirax_sprite_engine | open |
| H-007 | AI | Sprite line buffer = six 74S201 (256×1) at C9–H9, double-buffered | Six SN74S201N identified by silkscreen; wiring not traced | Trace address/data of C9–H9 | mirax_sprite_engine | open |
| H-008 | AI | Sound work RAM = HM6116 at P2 | Proximity to the sound Z80 (S2) only | Continuity S2 address/data → P2 | mirax_sound | open |
| H-009 | AI | Sound command latch = 74LS273 (P3) + 74LS245 (O4) | The '273 has no 3-state output and needs a buffer; the '245 is adjacent | Continuity '273 Q → '245 A; '245 B → sound data bus | mirax_sound | open |
| H-010 | TBD | Both AYs are mixed through identical 1K resistors (equal weight) | 1K resistors identified in photos; wiring not traced | Continuity from the AY analog outputs to the resistors and the amp input | mirax_sound, mirax_audio_out | open |
| H-011 | TBD | Output stage: MB3712, ~10 µF input coupling, 470 pF, no large shunt cap | Components identified in photos | Trace the amplifier input network; measure frequency response | mirax_audio_out | open |
| H-012 | TBD | CPU and video share VRAM/colorram through 74LS157 muxes on alternate dot-clock phases | 74LS157s present near the RAMs; not traced | Trace the '157 select inputs to the pixel-clock phase | mirax_video | open |
| H-013 | TBD | Presence and role of the third PROM (MAME `mirax.prm`, NO_DUMP) | **Conflict:** mirax_top says CT805-3 has none; mirax_decrypt says it may encode the scheme | Inspect the board for a third small PROM | mirax_top, mirax_decrypt | open |
| H-021 | AI | Colour DAC weights 1K/470/270 (R, G) and 470/270 (B); MAME assumes 1K/470/220 and 1K/470 | Silkscreen + colour bands at A12; MRA3 outputs traced to R1–R9 on the solder side (O7→R2 through a via, assumed) | Continuity O7↔R2; measure the fitted resistors; check the summing nodes and the load to ground | mirax_video (future mirax_palette) | open |
| H-022 | Human | MRA3/MRB3 = two 32-entry RGB332 banks selected by /CE, outputs in parallel | Consistent with MAME (64 entries, `color & 7`); short traces between the two PROMs | Check that pin 15 (/CE) of both PROMs are complementary and that O1–O8 are joined pin to pin | mirax_video (future mirax_palette) | open |
