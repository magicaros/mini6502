;=============================================================================
; desk3.asm - mini6502 desktop, bank $16: the icons
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; $E000 unpacks them into sprite images 0-47 (4 per icon,
; see icons.py), which the desktop STAMPs.
;=============================================================================

        .include "desk.inc"

        .org $E000

; --- icons: 1 bit + mask -> sprite images (0 paper, 1 ink, $80 see-through) ---
init:   lda #0                  ; port A -> $FD0000
        sta PADR
        sta PADR+1
        lda #$FD
        sta PADR+2
        lda #1
        sta PSTEP
        lda #0
        sta D0                  ; icon
@icon:  lda D0
        clc
        adc #>icondata
        sta DP+1
        lda #<icondata
        sta DP
        lda #0
        sta D0+1                ; quarter
@q:     lda #0
        sta D1                  ; row 0-15
@row:   lda D0+1                ; byte of the row = (16 * (q / 2) + row) * 4
        and #2                  ;   + 2 * (q AND 1)
        asl
        asl
        asl
        clc
        adc D1
        asl
        asl
        sta D1+1
        lda D0+1
        and #1
        asl
        clc
        adc D1+1
        tay
        jsr @eight
        iny
        jsr @eight
        inc D1
        lda D1
        cmp #16
        bne @row
        inc D0+1
        lda D0+1
        cmp #4
        bne @q
        inc D0
        lda D0
        cmp #12                 ; 12 icons (6: the desktop's disk, 7: a
                                ; folder, 8 song, 9 picture, 10 pixels,
                                ; 11 6502 source)
        bne @icon
        rts
@eight: lda (DP),y              ; 8 pixels: image byte, mask byte (+128)
        sta D2
        tya
        pha
        clc
        adc #128
        tay
        lda (DP),y
        sta D3
        pla
        tay
        ldx #8
@px:    asl D3                  ; mask bit
        bcs @on
        asl D2
        lda #$80
        bne @put
@on:    asl D2                  ; image bit
        lda #0
        rol
@put:   sta PDATA
        dex
        bne @px
        rts

icondata:
        .include "icons.inc"
