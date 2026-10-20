# Another World on Felipe's KN7000: the speed build's own figures (2026-10-20)

`AWPERF0.TXT`, `AWPERF1.TXT`: the reports the speed build (`KN7APP.BIN` `e3ee3a40...`, from the card's root) wrote at
two quits on the unit (program 893). Felipe's photo of the overlay and the SPEED 4/4 page is kept privately with
the dumps (technics_roms `real_dump_v1.3_b893/aw-speed-run1/`). Headlines:

| blit     | frames/s (whole run)                  | blit ms/frame | border ms/frame | LCD pixels/frame |
|----------|---------------------------------------|---------------|-----------------|------------------|
| new blit | 19.0-21.2 (25-30 in the last second)  | 22-27         | 1.4-1.7         | 3,500-5,300      |
| old blit | 1.5                                   | 268-270       | 347             | 128,000          |

The game's own benchmark measured LCD 16-bit stores at 1.3-1.8 us, three to four times pass 9's 439 ns: the LCD
is slower while the display is active (pass 9 also saw runs at 2.4x). Page operations (10-15 ms/frame) are now the
next cost after the blit.
