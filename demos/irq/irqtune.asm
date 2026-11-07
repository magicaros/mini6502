; irqtune.asm - background music on the frame interrupt       (bank RAM $E000)
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; A short original tune on the three music voices, with drums
; on the noise voice, played by an interrupt handler 60 times a second, so it
; keeps going while BASIC or the monitor runs. Everything (code, variables)
; is in this bank: no zero page, nothing in the fixed RAM.
;
;   $E000  start (or restart) the tune      $E003  stop it
; From the monitor: L IRQTUNE E000 0B / D020: 0B / E000R
; From BASIC:       POKE $D020,11:CALL $E000   (stop: POKE $D020,11:CALL $E003)
; Any bank works: the handler runs in the bank that was selected at start.

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

SPEED   = 7             ; frames per step

        jmp start
        jmp stop

start:  sei                     ; (nothing may fire half set up)
        lda #<handler
        sta IRQVEC
        lda #>handler
        sta IRQVEC+1
        lda BANK                ; the handler runs in this bank
        sta IRQBANK
        ldx #15                 ; the voices' settings
@v:     lda vset,x
        sta V1,x
        dex
        bpl @v
        lda #6                  ; a thin square for the melody
        sta S1+2
        lda #1
        sta TICK
        lda #0
        sta STEP
        lda #1                  ; the frame interrupt on
        sta IRQEN
        cli
        rts

stop:   lda #0
        sta IRQEN
        sta V1                  ; all notes off
        sta V2
        sta V3
        sta V4
        rts

; Called by the monitor's IRQ code with A = the sources that fired
handler:
        and #1                  ; FRAME?
        beq @done
        dec TICK
        bne @done
        lda #SPEED
        sta TICK
        ldx STEP
        lda melody,x
        beq @m
        sta V1
@m:     lda bass,x
        beq @b
        sta V2
@b:     lda arp,x
        sta V3
        ldy drums,x
        beq @d
        lda dvol-1,y            ; VOL, WAVE, DECAY then NOTE (which starts it)
        sta V4+1
        lda dwave-1,y
        sta V4+2
        lda #1
        sta S4
        lda dnote-1,y
        sta V4
@d:     inx
        txa
        and #31
        sta STEP
@done:  rts

TICK:   .byte 0
STEP:   .byte 0

;          NOTE VOL WAVE DUR
vset:   .byte 0, 9, 0, 6        ; melody: square
        .byte 0, 15, 1, 5       ; bass: triangle
        .byte 0, 4, 2, 3        ; arpeggio: sawtooth, quiet
        .byte 0, 12, 0, 0       ; drums: noise, ended by DECAY

; 32 steps; 0 = nothing new
melody: .byte 72,0,75,0,79,0,77,75, 74,0,72,0,74,75,77,0
        .byte 79,0,80,79,77,0,75,0, 74,72,74,0,72,0,0,0
bass:   .byte 36,0,48,0,36,0,48,0, 41,0,53,0,41,0,53,0
        .byte 44,0,56,0,44,0,56,0, 43,0,55,0,43,0,47,0
arp:    .byte 60,63,67,60,63,67,60,63, 60,65,68,60,65,68,60,65
        .byte 63,68,72,63,68,72,63,68, 62,67,71,62,67,71,62,67
drums:  .byte 1,0,3,0,2,0,3,0, 1,0,3,1,2,0,3,3
        .byte 1,0,3,0,2,0,3,0, 1,0,3,1,2,2,3,2
;              kick snare hat
dnote:  .byte 40, 92, 124
dvol:   .byte 15, 11, 5
dwave:  .byte 0, 0, 1
