; gfx.asm - GFX, the mini6502 BASIC extension for graphics, sound and the
; mouse (bank $00). See README.txt.
; Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
; personal, non-commercial use only (see basic/README.txt).
; mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.
;
;   L GFX E000 00     then start BASIC (A000R), or G / A003R back into it
; Commands (each starts with "!"; numbers are any expressions):
;   !SCREEN m               0 text, 1 graphics, 2 graphics + text, 3 hires,
;                           4 hires + text
;   !CLG [c]                clear the drawing page (colour c, else 0)
;   !COLOR c                the colour PLOT, LINE, BOX, FILL use (lores: a
;                           pixel byte 0-63; hires: 1 ink, 0 paper)
;   !PLOT x,y               a point
;   !LINE x0,y0,x1,y1       a line
;   !BOX x0,y0,x1,y1        a rectangle
;   !FILL x0,y0,x1,y1       a filled rectangle
;   !PIXEL x,y,V            V = the pixel at x,y
;   !PALETTE i,r,g,b        palette entry i (0-31) = r,g,b (0-255)
;   !PAGE show[,draw]       the page shown (and the one drawn on), 0-1
;   !SPRITE n,x,y[,i[,f]]   sprite n (0-31) at x,y (screen pixels), image i,
;                           flags f (1 on, 2 flip across, 4 flip down, 8
;                           double, 16 behind, 32 shadow); it is switched on
;   !SPROFF n               sprite n off
;   !SPRDEF n,a             sprite image n = the 256 bytes at address a
;   !SOUND v,n[,vol[,w[,d]]]  voice v (1-4) plays note n (0 = off): volume
;                           0-15, wave 0-3, duration in frames (0 = held)
;   !SHAPE v,decay[,sweep[,pulse]]  voice v's shaping
;   !QUIET                  all four voices off
;   !MUSIC b                the music engine plays the song in bank b
;                           (0 = stop)
;   !MOUSE X,Y,B            X,Y = where the mouse is (text: column, row;
;                           graphics: 160 x 200; hires: 640 x 400), B = its
;                           buttons (1 left, 2 right, 4 middle)
;   !WAIT n                 wait n frames (1/60 s each)
;   !POINTER n              the mouse pointer: 1 on, 0 off
;   !BLOAD "name",a[,b]     load a file at address a (with bank b at $E000)
;   !BSAVE "name",a,e[,b]   save a..e (end included), with bank b
;   !HELP                   list these commands (and every other
;                           extension's)
;   !FLUSH                  throw away the keys waiting to be read
; Functions (in expressions, e.g. X=!MOUSEX or IF !BUTTONS AND 1 THEN ...):
;   !MOUSEX  !MOUSEY        where the mouse is (units as for !MOUSE)
;   !BUTTONS                the buttons held (1 left, 2 right, 4 middle)
;   !CLICKS                 the buttons pressed since the last !CLICKS
;   !FRAME                  the frame counter (0-255, +1 every 1/60 s)
;   !PIXEL(x,y)             the pixel at x,y
;   !KEYDOWN("W")           -1 while that key is held down, else 0 (several
;   !KEYDOWN(code)          at once, no auto-repeat; codes: see KEYSEL);
;                           it also throws away the keys waiting to be read
;                           (but not a Ctrl-C), as !FLUSH
;   !KEYAT("W")            the same for the key in a PLACE, whatever the
;   !KEYAT(scancode)       layout: "W" = where W is on a US keyboard (Z on
;                           AZERTY), or a PC scancode (see KEYPOS)

        .include "mini6502.inc"
        .include "bx.inc"

PTRA    = $F8           ; 2: a pointer (SPRDEF)
T0      = $FA           ; scratch
T1      = $FB
T2      = $FC
T3      = $FD           ; (functions only)
T4      = $FE

        .org $E000
        .byte "BX", 2
        jmp statement           ; $E003
        jmp init                ; $E006
        jmp function            ; $E009
        .byte "GFX", 0, 0, 0, 0, 0      ; $E00C its name (8)
        .word keywords          ; $E014 its commands (for !HELP)
        .word fwords            ; $E016 its functions

init:   lda #1
        sta PEN
        rts

statement:
        ldx #<keywords
        ldy #>keywords
        jsr XMATCH
        bcs @no                 ; not ours
        asl
        tax
        lda cmds+1,x            ; run it (RTS goes to @done)
        pha
        lda cmds,x
        pha
        rts
@no:    rts

; a function: its value in Y (low) / A (high), carry clear
function:
        ldx #<fwords
        ldy #>fwords
        jsr XMATCH
        bcs @no
        asl
        tax
        lda fcmds+1,x
        pha
        lda fcmds,x
        pha
@no:    rts

fcmds:  .word f_mousex-1, f_mousey-1, f_buttons-1, f_clicks-1, f_frame-1
        .word f_pixel-1, f_keydown-1, f_keyat-1
fwords: .byte "MOUSE", 'X'+$80, "MOUSE", 'Y'+$80, "BUTTON", 'S'+$80
        .byte "CLICK", 'S'+$80, "FRAM", 'E'+$80, "PIXE", 'L'+$80
        .byte "KEYDOW", 'N'+$80, "KEYA", 'T'+$80
        .byte 0

f_mousex:
        jsr mousex
        clc
        rts
f_mousey:
        jsr mousey
        clc
        rts
f_buttons:
        ldy BUTTONS
        jmp byteval
f_clicks:
        ldy CLICKS
        jmp byteval
f_frame:
        ldy FRAME
byteval:
        lda #0
        clc
        rts
; (the blitter's X0/Y0 are put back: a command may be halfway through
; setting them up, as in !PLOT 5,!PIXEL(1,1))
f_pixel:
        jsr XCHRGOT             ; (x,y)
        cmp #'('
        bne @bad
        jsr XCHRGET
        jsr XGETWORD            ; x, kept on the stack
        lda Itempl
        pha
        lda Itemph
        pha
        jsr XCOMMA
        jsr XGETWORD            ; y
        jsr XCHRGOT
        cmp #')'
        bne @bad
        jsr XCHRGET
        pla
        sta T4
        pla
        sta T3
        lda BX0
        pha
        lda BX0H
        pha
        lda BY0
        pha
        lda BY0H
        pha
        lda T3
        sta BX0
        lda T4
        sta BX0H
        lda Itempl
        sta BY0
        lda Itemph
        sta BY0H
        lda BPIXEL
        sta T3
        pla
        sta BY0H
        pla
        sta BY0
        pla
        sta BX0H
        pla
        sta BX0
        ldy T3
        jmp byteval
@bad:   jmp XSYNTAX

; !KEYDOWN("W") or !KEYDOWN(code): -1 while that key is held, else 0
f_keydown:
        jsr flushkeys           ; (the typed copies of held keys: away)
        jsr XCHRGOT
        cmp #'('
        bne @bad
        jsr XCHRGET
        cmp #'"'                ; a string: its first character
        bne @num
        jsr XGETSTR
        stx PTRA
        sty PTRA+1
        tax                     ; (empty: code 0, never held)
        beq @code
        ldy #0
        lda (PTRA),y
        cmp #'a'
        bcc @up
        cmp #'z'+1
        bcs @up
        and #$DF
@up:    tax
        jmp @code
@num:   jsr XGETBYTE
@code:  stx KEYSEL
        jsr XCHRGOT
        cmp #')'
        bne @bad
        jsr XCHRGET
        ldy #0
        lda KEYHELD
        beq @r
        dey                     ; held: -1 ($FFFF), BASIC's "true"
@r:     tya
        clc
        rts
@bad:   jmp XSYNTAX

; !KEYAT("W") or !KEYAT(scancode): -1 while the key in that PLACE is held
; ("W" = where W is on a US keyboard: Z on AZERTY), else 0
f_keyat:
        jsr flushkeys
        jsr XCHRGOT
        cmp #'('
        bne @bad
        jsr XCHRGET
        cmp #'"'
        bne @num
        jsr XGETSTR             ; a letter, digit or space: its US position
        stx PTRA
        sty PTRA+1
        tax
        beq @bad
        ldy #0
        lda (PTRA),y
        cmp #' '
        beq @sp
        cmp #'a'
        bcc @nl
        and #$DF
@nl:    cmp #'A'
        bcc @dig
        cmp #'Z'+1
        bcs @bad
        tax
        lda usletter-'A',x
        jmp @set
@sp:    lda #57
        jmp @set
@dig:   cmp #'0'
        beq @zero
        bcc @bad
        cmp #'9'+1
        bcs @bad
        sbc #'0'-2              ; (carry clear: 1-9 -> 2-10)
        jmp @set
@zero:  lda #11
        jmp @set
@num:   jsr XGETBYTE
        txa
@set:   sta KEYPOS
        jsr XCHRGOT
        cmp #')'
        bne @bad
        jsr XCHRGET
        ldy #0
        lda POSHELD
        beq @r
        dey
@r:     tya
        clc
        rts
@bad:   jmp XFUNC
; PC scancodes of the letters A-Z on a US keyboard
usletter:
        .byte 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50
        .byte 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44

; the mouse in the units of the screen mode: Y low, A high
mousex: lda MODE
        beq @t
        cmp #3
        bcs @h
        ldy MOUSELX
        lda #0
        rts
@t:     ldy MOUSECOL
        lda #0
        rts
@h:     ldy MOUSEX
        lda MOUSEX+1
        rts
mousey: lda MODE
        beq @t
        cmp #3
        bcs @h
        ldy MOUSELY
        lda #0
        rts
@t:     ldy MOUSEROW
        lda #0
        rts
@h:     ldy MOUSEY
        lda MOUSEY+1
        rts

; the commands' ends come here: carry clear = done
done:   clc
        rts

        .include "bxmatch.inc"

; (in the order of the keyword list) - 1, for RTS
cmds:   .word c_screen-1, c_clg-1, c_color-1, c_plot-1, c_line-1, c_box-1
        .word c_fill-1, c_pixel-1, c_palette-1, c_page-1, c_sprite-1
        .word c_sproff-1, c_sprdef-1, c_sound-1, c_shape-1, c_quiet-1
        .word c_music-1, c_mouse-1, c_wait-1, c_pointer-1, c_bload-1
        .word c_bsave-1, c_help-1, c_flush-1
keywords:
        .byte "SCREE", 'N'+$80, "CL", 'G'+$80, "COLO", 'R'+$80
        .byte "PLO", 'T'+$80, "LIN", 'E'+$80, "BO", 'X'+$80
        .byte "FIL", 'L'+$80, "PIXE", 'L'+$80, "PALETT", 'E'+$80
        .byte "PAG", 'E'+$80, "SPRIT", 'E'+$80, "SPROF", 'F'+$80
        .byte "SPRDE", 'F'+$80, "SOUN", 'D'+$80, "SHAP", 'E'+$80
        .byte "QUIE", 'T'+$80, "MUSI", 'C'+$80, "MOUS", 'E'+$80
        .byte "WAI", 'T'+$80, "POINTE", 'R'+$80, "BLOA", 'D'+$80
        .byte "BSAV", 'E'+$80, "HEL", 'P'+$80, "FLUS", 'H'+$80
        .byte 0

PEN:    .byte 1                 ; the drawing colour

; --- helpers --------------------------------------------------------------------

; is there another argument? (a "," next: skipped, carry set)
more:   jsr XCHRGOT
        cmp #','
        bne @no
        jsr XCHRGET
        sec
        rts
@no:    clc
        rts

; x,y -> X0,Y0 (16 bits each, hires high bytes too)
getxy0: jsr XGETWORD
        lda Itempl
        sta BX0
        lda Itemph
        sta BX0H
        jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta BY0
        lda Itemph
        sta BY0H
        rts

; ,x1,y1 -> X1,Y1
getxy1: jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta BX1
        lda Itemph
        sta BX1H
        jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta BY1
        lda Itemph
        sta BY1H
        rts

; a byte after a ","
combyte:
        jsr XCOMMA
        jmp XGETBYTE

; the blitter command A with the pen colour
blit:   ldx PEN
        stx BCOL
        sta BCMD
        jmp done

; X = a voice 1-4: Y = its register offset (0, 4, 8, 12)
voice:  dex
        cpx #4
        bcs bad
        txa
        asl
        asl
        tay
        rts

bad:    jmp XFUNC

; --- graphics -------------------------------------------------------------------
c_screen:
        jsr XGETBYTE
        stx MODE
        jmp done

c_clg:  ldx #0
        jsr XCHRGOT
        beq @go
        jsr XGETBYTE
@go:    stx BCOL
        lda #C_CLEAR
        sta BCMD
        jmp done

c_color:
        jsr XGETBYTE
        stx PEN
        jmp done

c_plot: jsr getxy0
        lda #C_PSET
        jmp blit

c_line: jsr getxy0
        jsr getxy1
        lda #C_LINE
        jmp blit

c_box:  jsr getxy0
        jsr getxy1
        lda #C_BOX
        jmp blit

c_fill: jsr getxy0
        jsr getxy1
        lda #C_BOXF
        jmp blit

c_pixel:
        jsr getxy0
        jsr XCOMMA
        jsr XGETVAR
        ldy BPIXEL
        lda #0
        jsr XSETVAR
        jmp done

c_palette:
        jsr XGETBYTE
        cpx #32
        bcs bad
        stx PALIDX
        jsr combyte
        stx PALR
        jsr combyte
        stx PALG
        jsr combyte
        stx PALB
        jmp done

c_page: jsr XGETBYTE
        stx SHOW
        jsr more
        bcc @d
        jsr XGETBYTE
        stx DRAW
@d:     jmp done

; --- sprites --------------------------------------------------------------------
; sprite n -> T0 = n * 8 (its offset in SPR)
sprnum: jsr XGETBYTE
        cpx #32
        bcs @bad
        txa
        asl
        asl
        asl
        sta T0
        rts
@bad:   jmp XFUNC

c_sprite:
        jsr sprnum
        jsr XCOMMA
        jsr XGETWORD            ; x + 16
        clc
        lda Itempl
        adc #16
        ldx T0
        sta SPR,x
        jsr XCOMMA
        jsr XGETWORD            ; y + 16
        clc
        lda Itempl
        adc #16
        ldx T0
        sta SPR+1,x
        jsr more
        bcc @on
        jsr XGETBYTE            ; image
        txa
        ldx T0
        sta SPR+2,x
        jsr more
        bcc @on
        jsr XGETBYTE            ; flags
        txa
        ldx T0
        sta SPR+3,x
@on:    ldx T0
        lda SPR+3,x
        ora #1
        sta SPR+3,x
        jmp done

c_sproff:
        jsr sprnum
        ldx T0
        lda SPR+3,x
        and #$FE
        sta SPR+3,x
        jmp done

c_sprdef:
        jsr XGETBYTE            ; image n: $FD0000 + n * 256
        stx T0
        jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta PTRA
        lda Itemph
        sta PTRA+1
        lda #0
        sta PADR
        lda T0
        sta PADR+1
        lda #$FD
        sta PADR+2
        lda #1
        sta PSTEP
        ldy #0
@c:     lda (PTRA),y
        sta PDATA
        iny
        bne @c
        jmp done

; --- sound ----------------------------------------------------------------------
c_sound:
        jsr XGETBYTE            ; voice
        jsr voice
        sty T1
        jsr combyte             ; note (set last: it starts the sound)
        stx T2
        jsr more
        bcc @go
        jsr XGETBYTE
        ldy T1
        txa
        sta SND+V_VOL,y
        jsr more
        bcc @go
        jsr XGETBYTE
        ldy T1
        txa
        sta SND+V_WAVE,y
        jsr more
        bcc @go
        jsr XGETBYTE
        ldy T1
        txa
        sta SND+V_DUR,y
@go:    ldy T1
        lda T2
        sta SND+V_NOTE,y
        jmp done

c_shape:
        jsr XGETBYTE
        jsr voice
        sty T1
        jsr combyte             ; decay
        ldy T1
        txa
        sta SHP+S_DECAY,y
        jsr more
        bcc @d
        jsr XGETWORD            ; sweep, signed
        ldy T1
        lda Itempl
        sta SHP+S_SWEEP,y
        jsr more
        bcc @d
        jsr XGETBYTE            ; pulse
        ldy T1
        txa
        sta SHP+S_PULSE,y
@d:     jmp done

c_quiet:
        lda #0
        sta V1+V_NOTE
        sta V2+V_NOTE
        sta V3+V_NOTE
        sta V4+V_NOTE
        jmp done

; !MUSIC b: the engine (bank B_MUSIC, "MUSIC" at $E006) must be there
c_music:
        jsr XGETBYTE
        stx T0
        lda #$06                ; look for its name at $E006, through port A
        sta PADR
        lda #<(B_MUSIC << 4)
        sta PADR+1
        lda #>(B_MUSIC << 4)
        sta PADR+2
        lda #1
        sta PSTEP
        ldy #0
@n:     lda PDATA
        cmp s_music,y
        bne bad2
        iny
        cpy #5
        bne @n
        ldx T0
        beq @stop
        lda #0                  ; PLAY bank X
        jsr E_MUSIC
        bcs bad2                ; not a song
        jmp done
@stop:  lda #1                  ; STOP
        jsr E_MUSIC
        jmp done
bad2:   jmp XFUNC
s_music: .byte "MUSIC"

; --- mouse, time ------------------------------------------------------------------
c_mouse:
        jsr XGETVAR             ; X
        jsr mousex
        jsr XSETVAR
        jsr XCOMMA
        jsr XGETVAR             ; Y
        jsr mousey
        jsr XSETVAR
        jsr XCOMMA
        jsr XGETVAR             ; B
        ldy BUTTONS
        lda #0
        jsr XSETVAR
        jmp done

c_wait: jsr XGETWORD
@f:     lda Itempl
        ora Itemph
        beq @d
        lda FRAME
@w:     cmp FRAME
        beq @w
        lda Itempl
        bne @l
        dec Itemph
@l:     dec Itempl
        jmp @f
@d:     jmp done

c_pointer:
        jsr XGETBYTE
        txa
        beq @s
        lda #3                  ; shown, following the mouse
@s:     sta PTR
        jmp done

; --- disk -----------------------------------------------------------------------
; "name" -> DNAME / DNLEN
fname:  jsr XGETSTR
        sta DNLEN
        stx DNAME
        sty DNAME+1
        rts

; [,bank] -> X (else the program's bank); a free bank becomes "by hand"
fbank:  jsr more
        bcc @own
        jsr XGETBYTE
        lda BANKMAP,x
        bne @r
        lda #OWN_HAND
        sta BANKMAP,x
@r:     rts
@own:   ldx XBANK
        rts

c_bload:
        jsr fname
        jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta DSTART
        lda Itemph
        sta DSTART+1
        lda #0                  ; no limit
        sta DEND
        sta DEND+1
        jsr fbank
        lda #3                  ; LOAD at DSTART
        jsr XDISK
        jmp done

c_bsave:
        jsr fname
        jsr XCOMMA
        jsr XGETWORD
        lda Itempl
        sta DSTART
        lda Itemph
        sta DSTART+1
        jsr XCOMMA
        jsr XGETWORD            ; the end, included: END = it + 1
        clc
        lda Itempl
        adc #1
        sta DEND
        lda Itemph
        adc #0
        sta DEND+1
        jsr fbank
        lda #2                  ; SAVE
        jsr XDISK
        jmp done

; !FLUSH: the keys waiting to be read are thrown away
c_flush:
        jsr flushkeys
        jmp done

; Takes every waiting key except a Ctrl-C (BASIC's break must still work).
; A program steering with !KEYDOWN would otherwise leave the held keys'
; typed copies (auto-repeat and all) for BASIC to find when it stops.
flushkeys:
        lda KBDPEEK
        beq @r                  ; none
        and #$7F
        cmp #3
        beq @r
        lda KBD
        jmp flushkeys
@r:     rts

; --- help -----------------------------------------------------------------------
; !HELP: every extension's commands and functions
c_help: jmp bxhelp

        .include "bxhelp.inc"

        .assert * <= $F000, error, "GFX must fit in its bank"
