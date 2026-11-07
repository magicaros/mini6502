;=============================================================================
; win.inc - window geometry helpers, assembled into toolkit banks 1 and 3
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;=============================================================================

; WP = window X's record
winptr:
        txa
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<WINREC
        sta WP
        lda #>WINREC
        adc #0
        sta WP+1
        rts

; RX0..RY1 = outer rectangle of window X (+ shadow if carry set on entry)
winrect:
        php
        jsr winptr
        ldy #W_X0
@c:     lda (WP),y
        sta RX0-W_X0,y
        iny
        cpy #W_Y1+2
        bne @c
        plp
        bcc @r
        ADDW RX1, RX1, 2
        ADDW RY1, RY1, 2
@r:     rts

; RX0..RY1 = content of window X
wincontent:
        clc
        jsr winrect
        ADDW RX0, RX0, 1
        ADDW RY0, RY0, TITLEH + 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        rts

; RX0..RY1 = title bar of window X
wintitle:
        clc
        jsr winrect
        ADDW RY1, RY0, TITLEH
        rts

; damage += RX0..RY1
adddamage:
        lda DAMAGE
        bne @union
        ldx #7
@c:     lda RX0,x
        sta DX0,x
        dex
        bpl @c
        inc DAMAGE
        rts
@union: ldx #0                  ; DX0 = min, DY0 = min (x = 0, 2)
        jsr @min
        ldx #2
        jsr @min
        ldx #4                  ; DX1 = max, DY1 = max
        jsr @max
        ldx #6
@max:   lda DX0,x               ; D >= R ? keep
        cmp RX0,x
        lda DX0+1,x
        sbc RX0+1,x
        bcs @k
        bcc @take
@min:   lda RX0,x               ; R >= D ? keep
        cmp DX0,x
        lda RX0+1,x
        sbc DX0+1,x
        bcs @k
@take:  lda RX0,x
        sta DX0,x
        lda RX0+1,x
        sta DX0+1,x
@k:     rts

