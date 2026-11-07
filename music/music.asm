; music.asm - the mini6502 music engine                   (bank $12, $E000)
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Plays a song (a .MUS file, see README.txt) on the three
; music voices from the frame interrupt, so it keeps playing while other
; programs run. The noise voice (voice 4) is left to programs: sound
; effects never steal a note from the music.
;
; Calling it (far-call entries $19 MUSIC and $1A MUSICB, in VECTORS):
;   assembly  LDA #function : LDX #argument : JSR $CCD0      (entry $19)
;   BASIC     POKE 52446,function:POKE 52447,argument:CALL 52440 (entry $1A)
;             (52446/52447 = $CCDE/$CCDF, the spare bytes of entry $1A)
; Functions:
;   0 PLAY      X = the bank where the song starts (it may go on into the
;               next banks). Carry set (and nothing played) if it is not a
;               song. Takes the interrupt: IRQVEC, IRQBANK, IRQEN bit 0.
;   1 STOP      the music stops, the interrupt is let go
;   2 PAUSE     the voices are released; 3 CONTINUE carries on
;   4 STATUS    A = 0 stopped, 1 playing, 2 paused; X = order, Y = row
;               (BASIC: $CCDE = state, $CCDF = order)
;   5 VOLUME    X = 0-15, the loudness of the whole song (15 at first;
;               from each voice's next instrument or volume on)
;
; Inside the interrupt the engine uses port B (put back as it was), the
; voices 1-3 and nothing else: no zero page, no fixed RAM, all its
; variables are in this bank.

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

BOXFN   = $CCDE         ; BASIC's mailbox (spare bytes of entry $1A)
BOXARG  = $CCDF

NVOICE  = 3
; effects (column 3 of a pattern row; the 4th byte is its parameter)
FX_ARP  = 1             ; arpeggio: note, +hi nibble, +lo nibble semitones
FX_SLIDE = 2            ; SWEEP = parameter (signed) for this row
FX_VIB  = 3             ; vibrato: speed (hi nibble), depth (lo nibble)
FX_VOL  = 4             ; volume = parameter (0-15)
FX_SPEED = 5            ; frames per row = parameter
FX_JUMP = 6             ; after this row, go to order = parameter
FX_BREAK = 7            ; after this row, go to the next order
FX_PULSE = 8            ; PULSE = parameter (0-15)

.segment "CODE"
        jmp api                 ; $E000: A = function, X = argument
        jmp apibox              ; $E003: the same from BASIC's mailbox
        .byte "MUSIC", 0        ; (for whoever looks)

apibox: lda BOXFN
        ldx BOXARG
        jsr api
        sta BOXFN
        stx BOXARG
        rts

api:    cmp #0
        bne :+
        jmp play
:       cmp #1
        bne :+
        jmp stop
:       cmp #2
        bne :+
        jmp pause
:       cmp #3
        bne :+
        lda STATE
        cmp #2
        bne @ok
        lda #1
        sta STATE
@ok:    clc
        rts
:       cmp #4
        bne :+
        lda STATE
        ldx ORDER
        ldy ROW
        clc
        rts
:       cmp #5
        bne :+
        txa
        and #15
        sta MVOL
        clc
        rts
:       sec                     ; unknown function
        rts

; --- PLAY ------------------------------------------------------------------
play:   lda #0                  ; the interrupt leaves us alone meanwhile
        sta STATE
        jsr silence
        stx SBASE+2             ; song start = bank * 4096
        txa
        asl
        asl
        asl
        asl
        sta SBASE+1
        lda SBASE+2
        lsr
        lsr
        lsr
        lsr
        sta SBASE+2
        lda #0
        sta SBASE
        jsr savepb
        lda #0                  ; the header
        sta T0
        sta T0+1
        jsr seek
        ldx #0
@h:     lda PBDATA
        sta HDR,x
        inx
        cpx #16
        bne @h
        lda HDR
        cmp #'M'
        bne @bad
        lda HDR+1
        cmp #'U'
        beq @good
@bad:   jsr restpb
        sec
        rts
@good:  lda HDR+3
        sta SPEED
        lda HDR+4
        sta NORD
        lda HDR+5
        sta LOOP
        lda HDR+6
        sta ROWS
        lda HDR+7
        sta NINS
        lda HDR+12
        sta PATOFF
        lda HDR+13
        sta PATOFF+1
        lda #16                 ; the instruments, 8 bytes each, from byte 16
        sta T0
        lda #0
        sta T0+1
        jsr seek
        lda NINS
        asl
        asl
        asl
        sta T1                  ; (0 = 256: 32 instruments)
        ldx #0
@i:     lda PBDATA
        sta INSTR,x
        inx
        cpx T1
        bne @i
        lda HDR+10              ; the order list, 3 pattern numbers each
        sta T0
        lda HDR+11
        sta T0+1
        jsr seek
        ldx #0
@o:     lda PBDATA
        sta ORD0,x
        lda PBDATA
        sta ORD1,x
        lda PBDATA
        sta ORD2,x
        inx
        cpx NORD
        bne @o
        jsr restpb
        ldx #NVOICE - 1         ; the voices from scratch
@v:     lda #0
        sta VINS,x
        sta VEFF,x
        sta VPAR,x
        sta VVIB,x
        sta VPH,x
        dex
        bpl @v
        lda #0
        sta ORDER
        sta ROW
        sta ARPC
        lda #$FF
        sta NEXTORD
        lda #1                  ; row 0 at the next frame
        sta TICK
        jsr setorder
        lda #<handler           ; the frame interrupt is ours
        sta IRQVEC
        lda #>handler
        sta IRQVEC+1
        lda BANK
        sta IRQBANK
        sta MYBANK
        lda IRQEN
        ora #1
        sta IRQEN
        lda #1
        sta STATE
        cli
        clc
        rts

; --- STOP, PAUSE -------------------------------------------------------------
stop:   lda #0
        sta STATE
        jsr silence
        lda IRQVEC              ; let go of the interrupt if it is still ours
        cmp #<handler
        bne @n
        lda IRQVEC+1
        cmp #>handler
        bne @n
        lda IRQBANK
        cmp MYBANK
        bne @n
        lda #0
        sta IRQEN
@n:     clc
        rts

pause:  lda STATE
        cmp #1
        bne @n
        lda #2
        sta STATE
        jsr silence
@n:     clc
        rts

; Voices 1-3 released, their sweeps and bends back to 0 (keeps X)
silence:
        ldy #(NVOICE - 1) * 4
@s:     lda #0
        sta SND,y               ; NOTE 0: released (fades out)
        sta SHP+1,y
        sta SHP+3,y
        dey
        dey
        dey
        dey
        bpl @s
        rts

; --- the interrupt ------------------------------------------------------------
handler:
        and #1                  ; a frame?
        beq @r
        lda STATE
        cmp #1
        bne @r
        jsr savepb
        dec TICK
        bne @f
        lda SPEED
        sta TICK
        jsr dorow
        lda STATE               ; (the song may have ended)
        cmp #1
        bne @x
@f:     jsr doframe
@x:     jsr restpb
@r:     rts

; One row: each voice's cell, then on to the next row
dorow:  ldx #0
@v:     stx CURV
        txa                     ; T0 = pattern start + ROW * 4
        asl
        asl
        tay                     ; (Y = voice * 4, kept for the registers)
        sty CURVY
        lda ROW
        asl
        asl
        clc
        adc PADDR0,x
        sta PBADR
        lda PADDR1,x
        adc #0
        sta PBADR+1
        lda PADDR2,x
        adc #0
        sta PBADR+2
        lda #1
        sta PBSTEP
        lda PBDATA
        sta CNOTE
        lda PBDATA
        sta CINS
        lda PBDATA
        sta CEFF
        lda PBDATA
        sta CPAR
        jsr docell
        ldx CURV
        inx
        cpx #NVOICE
        bne @v
        lda NEXTORD             ; a jump or a break
        cmp #$FF
        beq @next
        sta ORDER
        lda #$FF
        sta NEXTORD
        lda #0
        sta ROW
        jmp @neword
@next:  inc ROW
        lda ROW
        cmp ROWS
        bcc @done
        lda #0
        sta ROW
        inc ORDER
@neword: lda ORDER
        cmp NORD
        bcc @in
        lda LOOP                ; the end: loop, or stop
        cmp #$FF
        bne @lp
        lda #0
        sta STATE
        jmp silence
@lp:    sta ORDER
@in:    jmp setorder
@done:  rts

; The cell of voice CURV (Y = CURV * 4)
docell: ldx CURV
        lda CINS                ; a new instrument
        beq @noins
        cmp NINS
        beq @insok
        bcs @noins              ; (not in the song: ignored)
@insok: sta VINS,x
        jsr insidx              ; X = its first byte in INSTR
        lda INSTR+2,x           ; WAVE
        sta SND+2,y
        lda INSTR+1,x           ; VOL (times the song's volume)
        jsr scalevol
        sta SND+1,y
        lda INSTR+0,x           ; DECAY
        sta SHP+0,y
        lda INSTR+4,x           ; PULSE
        sta SHP+2,y
        lda INSTR+5,x           ; DUR
        sta SND+3,y
        lda INSTR+6,x           ; the instrument's vibrato
        ldx CURV
        sta VVIB,x
@noins: ldx CURV
        lda CEFF                ; nothing new (no note, no effect): the
        ora CNOTE               ; arpeggio, vibrato or slide goes on
        bne @chg
        rts
@chg:   lda CEFF
        sta VEFF,x
        lda CPAR
        sta VPAR,x
        lda CEFF                ; SWEEP: the effect's for this row, else
        cmp #FX_SLIDE           ; the instrument's
        bne @nosl
        lda CPAR
        sta SHP+1,y
        jmp @fx
@nosl:  lda VINS,x
        beq @fx
        jsr insidx
        lda INSTR+3,x
        sta SHP+1,y
        ldx CURV
@fx:    lda CEFF
        cmp #FX_VOL
        bne :+
        lda CPAR
        jsr scalevol
        sta SND+1,y
        jmp @note
:       cmp #FX_SPEED
        bne :+
        lda CPAR
        beq @note
        sta SPEED
        sta TICK
        jmp @note
:       cmp #FX_JUMP
        bne :+
        lda CPAR
        sta NEXTORD
        jmp @note
:       cmp #FX_BREAK
        bne :+
        ldx ORDER
        inx
        stx NEXTORD
        ldx CURV
        jmp @note
:       cmp #FX_PULSE
        bne :+
        lda CPAR
        sta SHP+2,y
        jmp @note
:       cmp #FX_VIB
        bne @note
        lda CPAR
        sta VVIB,x
@note:  lda CNOTE
        beq @r
        cmp #$FF
        bne @on
        lda #0                  ; note off: released
        sta SND,y
@r:     rts
@on:    lda #0
        sta VPH,x
        sta SHP+3,y             ; (no bend left from before)
        lda CNOTE
        sta SND,y               ; (written last: it starts the note)
        rts

; X = (VINS,x - 1) * 8, the instrument's first byte in INSTR
insidx: lda VINS,x
        sec
        sbc #1
        asl
        asl
        asl
        tax
        rts

; A (0-15) times MVOL / 15
scalevol:
        and #15
        sta T1
        lda MVOL
        asl
        asl
        asl
        asl
        ora T1
        stx T1
        tax
        lda VOLT,x
        ldx T1
        rts

; Every frame: arpeggios and vibratos, as BEND (in 1/8 semitones)
doframe:
        inc ARPC
        lda ARPC
        cmp #3
        bcc :+
        lda #0
        sta ARPC
:       ldx #0
@v:     txa
        asl
        asl
        tay
        lda #0
        sta T1                  ; the bend
        lda VEFF,x
        cmp #FX_ARP
        bne @vib
        lda VPAR,x
        beq @vib
        ldy ARPC                ; 0: the note, 1: + hi nibble, 2: + lo
        beq @vibr
        dey
        bne @lo
        lsr
        lsr
        lsr
        lsr
@lo:    and #15
        asl                     ; semitones * 8
        asl
        asl
        sta T1
@vibr:  txa
        asl
        asl
        tay
@vib:   lda VVIB,x              ; speed (hi nibble), depth (lo nibble)
        beq @set
        and #$F0                ; phase += speed * 4 (a cycle in 64/speed
        lsr                     ; frames)
        lsr
        clc
        adc VPH,x
        sta VPH,x
        lsr                     ; triangle step -8..+8 from the phase
        lsr
        lsr
        lsr
        sty CURVY
        tay
        lda tri,y
        sta T2
        lda VVIB,x
        and #15
        tay
        lda #0                  ; T2 * depth / 8
@m:     cpy #0
        beq @md
        clc
        adc T2
        dey
        jmp @m
@md:    cmp #$80                ; signed / 8
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        clc
        adc T1
        sta T1
        ldy CURVY
@set:   lda T1
        sta SHP+3,y
        inx
        cpx #NVOICE
        bne @v
        rts

tri:    .byte 0, 2, 4, 6, 8, 6, 4, 2, 0, <-2, <-4, <-6, <-8, <-6, <-4, <-2

; Each voice's pattern for ORDER: song + PATOFF + pattern * ROWS * 4
setorder:
        ldx #0
@v:     ldy ORDER
        cpx #1
        beq @o1
        bcs @o2
        lda ORD0,y
        jmp @p
@o1:    lda ORD1,y
        jmp @p
@o2:    lda ORD2,y
@p:     sta T1                  ; T2:T3 = pattern * ROWS (8 x 8 bits)
        lda #0
        sta T2
        sta T3
        sta T4                  ; (the third byte of * 4)
        ldy #8
@mul:   asl T2
        rol T3
        asl T1
        bcc @nb
        clc
        lda T2
        adc ROWS
        sta T2
        lda T3
        adc #0
        sta T3
@nb:    dey
        bne @mul
        asl T2                  ; * 4
        rol T3
        rol T4
        asl T2
        rol T3
        rol T4
        clc                     ; + PATOFF + the song's start
        lda T2
        adc PATOFF
        sta T2
        lda T3
        adc PATOFF+1
        sta T3
        lda T4
        adc #0
        sta T4
        clc
        lda T2
        adc SBASE
        sta PADDR0,x
        lda T3
        adc SBASE+1
        sta PADDR1,x
        lda T4
        adc SBASE+2
        sta PADDR2,x
        inx
        cpx #NVOICE
        beq :+
        jmp @v
:       rts

; Port B to the song's byte T0 (16 bits), step 1
seek:   clc
        lda SBASE
        adc T0
        sta PBADR
        lda SBASE+1
        adc T0+1
        sta PBADR+1
        lda SBASE+2
        adc #0
        sta PBADR+2
        lda #1
        sta PBSTEP
        rts

; Port B kept / put back (it belongs to whoever we interrupted)
savepb: lda PBADR
        sta SAVPB
        lda PBADR+1
        sta SAVPB+1
        lda PBADR+2
        sta SAVPB+2
        lda PBSTEP
        sta SAVPB+3
        rts
restpb: lda SAVPB
        sta PBADR
        lda SAVPB+1
        sta PBADR+1
        lda SAVPB+2
        sta PBADR+2
        lda SAVPB+3
        sta PBSTEP
        rts

; volume table: VOLT[master * 16 + vol] = vol * master / 15, rounded
VOLT:
.repeat 16, M
  .repeat 16, V
        .byte (V * M + 7) / 15
  .endrepeat
.endrepeat

; --- variables (in this bank) -------------------------------------------------
STATE:  .byte 0                 ; 0 stopped, 1 playing, 2 paused
MVOL: .byte 15
MYBANK: .byte 0
SBASE:  .res 3                  ; the song's extended address
HDR:    .res 16
SPEED:  .byte 0
TICK:   .byte 0
ROW:    .byte 0
ORDER:  .byte 0
NEXTORD: .byte 0
NORD:   .byte 0
LOOP:   .byte 0
ROWS:   .byte 0
NINS:   .byte 0
PATOFF: .res 2
ARPC:   .byte 0
SAVPB:  .res 4
T0:     .res 2
T1:     .byte 0
T2:     .byte 0
T3:     .byte 0
T4:     .byte 0
CURV:   .byte 0
CURVY:   .byte 0
CNOTE:  .byte 0
CINS:   .byte 0
CEFF:   .byte 0
CPAR:   .byte 0
PADDR0: .res NVOICE             ; each voice's pattern (extended address)
PADDR1: .res NVOICE
PADDR2: .res NVOICE
VINS:   .res NVOICE             ; instrument, effect, parameter, vibrato,
VEFF:   .res NVOICE             ; vibrato phase
VPAR:   .res NVOICE
VVIB:   .res NVOICE
VPH:    .res NVOICE
INSTR:  .res 256                ; up to 32 instruments of 8 bytes
ORD0:   .res 256                ; the order list: voice 1, 2, 3 patterns
ORD1:   .res 256
ORD2:   .res 256
        .assert * <= $F000, error, "the music engine must fit in its bank"
