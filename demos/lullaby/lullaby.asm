;=============================================================================
; lullaby.asm - mini6502 sound demo                         (bank RAM $E000-$EFFF)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Plays Brahms' Lullaby (Wiegenlied, Op. 49 No. 4, 1868; the
; melody is in the public domain) on the three sound voices, with a little
; display of what each voice is playing. Any key stops it.
;
;   L LULLABY E000 08     load into bank 8 (any bank works)
;   D020: 08              select it
;   E000R                 play; a key stops and returns to the monitor
;
; Voice 1 melody (triangle), voice 2 bass (triangle), voice 3 harmony
; (sawtooth, quiet). Timing comes from the FRAME counter ($D001), so the
; tempo stays the same whatever CPU_HZ is. The song (song.inc) is made by
; song.py: three streams of (note, length in eighths, DUR) events.
;
; Uses $E2-$E3 of the zero page (free unless a far call is in progress) and
; $02A0-$02BF; RAM, BASIC and the monitor are left alone.
;=============================================================================


        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

P       = $E2           ; 2: stream pointer
IDX     = $02A0         ; 3: position in each stream
CNT     = $02A3         ; 3: ticks left of each voice's current event
OLDX    = $02A6         ; 3: column of each voice's marker on screen
LASTF   = $02A9         ; FRAME seen last
WAITN   = $02AA         ; frames left in this tick
SAVCOL  = $02AB         ; COLOR on entry
VOFF    = $02AC         ; voice * 4
NOTE    = $02AD

ROW0    = 12            ; screen row of voice 1's track (then +3, +6)
COL0    = 30            ; marker column = note - COL0

        .org $E000

        jmp play                ; $E000

play:
        cld
        lda COLOR
        sta SAVCOL
        lda #$01                ; dark blue background, for the night
        sta COLOR
        lda #2
        sta SYSCTL              ; clear the screen (in that colour)
        jsr title

        ldx #2                  ; set up the voices and the streams
@init:  txa
        asl
        asl
        tay
        lda vols,x
        sta V1+1,y
        lda waves,x
        sta V1+2,y
        lda #0
        sta IDX,x
        sta OLDX,x
        lda #1                  ; fetch an event on the first tick
        sta CNT,x
        dex
        bpl @init
        lda FRAME
        sta LASTF

; --- one tick (an eighth note) ---------------------------------------------------
tick:
        ldx #0
@voice: dec CNT,x
        bne @next
        jsr fetch               ; this voice's event is over: start the next
@next:  inx
        cpx #3
        bcc @voice

        lda #TICK               ; wait TICK frames, watching the keyboard
        sta WAITN
@wait:  lda KBDCR
        bmi stop
        lda FRAME
        cmp LASTF
        beq @wait
        sta LASTF
        dec WAITN
        bne @wait
        jmp tick

; --- a key: silence, back to the monitor ---------------------------------------
stop:
        lda KBD                 ; take the key
        ldx #2
@off:   txa
        asl
        asl
        tay
        lda #0                  ; release: the notes fade out
        sta V1,y
        dex
        bpl @off
        lda SAVCOL
        sta COLOR
        lda #2
        sta SYSCTL
        rts                     ; R ran us with JSR: back to the prompt

; --- next event of voice X ---------------------------------------------------------
fetch:
        lda slo,x
        sta P
        lda shi,x
        sta P+1
        ldy IDX,x
        lda (P),y
        cmp #$FF                ; end of the song: from the top
        bne @event
        lda #0
        sta IDX,x
        tay
        lda (P),y
@event: sta NOTE
        iny
        lda (P),y               ; length in ticks
        sta CNT,x
        iny
        txa
        asl
        asl
        sta VOFF
        lda (P),y               ; DUR in frames
        pha
        iny
        tya
        sta IDX,x
        pla
        ldy VOFF
        sta V1+3,y              ; DUR first: the NOTE write uses it
        lda NOTE
        beq @rest
        sta V1,y                ; play it
@rest:  ; fall into the display

; Moves voice X's marker to its note's column (or hides it for a rest)
marker:
        txa                     ; row = ROW0 + 3*X
        sta VOFF
        asl
        adc VOFF
        adc #ROW0
        sta CURY
        lda OLDX,x              ; erase the old marker
        beq @new
        sta CURX
        lda #' '
        sta VCHR
@new:   lda NOTE
        beq @hide
        sec
        sbc #COL0
        sta OLDX,x
        sta CURX
        lda glyphs,x
        sta VCHR
        lda colors,x
        sta VCOL
        rts
@hide:  lda #0
        sta OLDX,x
        rts

; --- title screen ------------------------------------------------------------------
title:
        lda #$0F                ; white on blue
        sta COLOR
        ldx #<t1
        ldy #>t1
        lda #2
        jsr at
        lda #$0B                ; light cyan
        sta COLOR
        ldx #<t2
        ldy #>t2
        lda #4
        jsr at
        lda #$07
        sta COLOR
        ldx #<t3
        ldy #>t3
        lda #5
        jsr at
        ldx #<t4
        ldy #>t4
        lda #8
        jsr at
        lda #$0E                ; labels in yellow
        sta COLOR
        ldx #<l1
        ldy #>l1
        lda #ROW0
        jsr at
        ldx #<l2
        ldy #>l2
        lda #ROW0+3
        jsr at
        ldx #<l3
        ldy #>l3
        lda #ROW0+6
        jsr at
        lda #$09                ; light blue
        sta COLOR
        ldx #<t5
        ldy #>t5
        lda #22
        jsr at
        lda #$07
        sta COLOR
        rts

; Prints the zero-terminated string at YX on row A, column 2
at:
        sta CURY
        lda #2
        sta CURX
        stx P
        sty P+1
        ldy #0
@loop:  lda (P),y
        beq @done
        sta DSP
        iny
        bne @loop
@done:  rts

t1:     .byte "mini6502 sound demo", 0
t2:     .byte "Lullaby (Wiegenlied), Op. 49 No. 4", 0
t3:     .byte "Johannes Brahms, 1868 - public domain", 0
t4:     .byte "3 voices: melody (triangle), bass (triangle), harmony (sawtooth)", 0
l1:     .byte "Melody", 0
l2:     .byte "Bass", 0
l3:     .byte "Harmony", 0
t5:     .byte "Press any key to stop", 0

slo:    .byte <s_melody, <s_bass, <s_harmony
shi:    .byte >s_melody, >s_bass, >s_harmony
vols:   .byte 15, 10, 5
waves:  .byte 1, 1, 2
glyphs: .byte 14, 219, 254      ; a note sign, a block, a small square (CP437)
colors: .byte $1F, $1D, $1B     ; on the blue background: white, magenta, cyan

        .include "song.inc"

        .assert * <= $F000, error, "the demo must fit in $E000-$EFFF"
