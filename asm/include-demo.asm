; Ctrl+A assembles this source using the supplied hardware definitions.
.include "hardware.inc"
.org $0300
        lda #'A'
        sta DSP
        lda #13
        sta DSP
        rts
