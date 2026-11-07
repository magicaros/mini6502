;=============================================================================
; tk2.asm - mini6502 desktop toolkit, bank $11: menus and dialogs
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Called from bank $10 (tk1.asm) through the jump table.
;=============================================================================

        .include "tk.inc"

        .org $E000

        jmp m_setbar            ; $E000
        jmp m_item              ; $E003
        jmp m_track             ; $E006
        jmp m_key               ; $E009
        jmp d_alert             ; $E00C
        jmp d_ask               ; $E00F

; --- menus ---------------------------------------------------------------------------------
; Definition (caller's memory): for each menu its title, 0, then its items,
; each ending with 0, then an empty item (a lone 0); after the last menu an
; empty title. Item "-" is a separator line; an item starting with "(" is
; disabled; an item ending with "/X" has the shortcut Ctrl+X.

m_setbar:
        MOVW T0, r0
        jsr farptr
        LDW QP, MTEXT
        lda #0
        sta NMENU
        sta NITEM
        sta ACCST
        lda #$FF
        sta ACCITEM
@menu:  ldx NMENU
        lda QP                  ; the title
        sta MTL,x
        lda QP+1
        sta MTH,x
        jsr getstr
        bne @t
        jmp @done               ; empty title: the end
@t:     sty TLEN
        iny                     ; width so far: the title + 2
        iny
        tya
        ldx NMENU
        sta MWIDTH,x
        lda NITEM
        sta MFIRST,x
        lda #0
        sta MCOUNT,x
        jsr advance
@item:  ldx NITEM
        lda QP
        sta IPL,x
        lda QP+1
        sta IPH,x
        lda #1
        sta IFLAG,x
        lda #0
        sta IKEY,x
        jsr getstr
        bne @i
        lda NMENU               ; the end of the first menu: the desk
        bne @endm               ; accessories' items follow (from their
        lda ACCST               ; bank), then the program's next menu
        bne @back
        inc ACCST
        ldx #2
@sv:    lda PBADR,x
        sta PBSAVE,x
        dex
        bpl @sv
        lda #<$E009
        sta PBADR
        lda #(>$E009 & $0F) | ((ACCBANK << 4) & $F0)
        sta PBADR+1
        lda #ACCBANK >> 4
        sta PBADR+2
        lda PBDATA              ; there? ("AC")
        cmp #'A'
        bne @back
        lda PBDATA
        cmp #'C'
        bne @back
        lda MCOUNT
        sta ACCITEM
        jmp @item
@back:  lda ACCST               ; back to the program's definition
        cmp #1
        bne @endm
        inc ACCST
        ldx #2
@rs:    lda PBSAVE,x
        sta PBADR,x
        dex
        bpl @rs
@endm:  jsr advance             ; empty: the end of this menu's items
        inc NMENU
        lda NMENU
        cmp #MAXMENU
        beq @full
        jmp @menu
@full:  jmp @done
@i:     sty TLEN
        ldy #0
        lda (QP),y
        cmp #'-'                ; separator
        bne @dis
        iny
        lda (QP),y
        bne @dis
        lda #2
        sta IFLAG,x
        bne @wid
@dis:   ldy #0
        lda (QP),y
        cmp #'('                ; disabled: "(" not shown
        bne @key
        lda #0
        sta IFLAG,x
        inc IPL,x
        bne @k0
        inc IPH,x
@k0:    dec TLEN
@key:   jsr shortcut            ; "/X" at the end
@wid:   lda TLEN                ; width: text + 6 (+4 for "^X")
        clc
        adc #2
        ldy IKEY,x
        beq @w
        adc #4
@w:     ldy NMENU
        cmp MWIDTH,y
        bcc @nw
        sta MWIDTH,y
@nw:    ldy NMENU
        lda MCOUNT,y
        clc
        adc #1
        sta MCOUNT,y
        jsr advance
        inc NITEM
        lda NITEM
        cmp #MAXITEM
        bcs @done
        jmp @item
@done:  jsr layout
        jmp m_drawbar

ACCST:  .byte 0                  ; 0, 1 reading the accessories', 2 done
PBSAVE: .res 3

; Looks for "/X" at the end of item X's text (TLEN characters from IPL/IPH)
shortcut:
        lda IPL,x
        sta TP
        lda IPH,x
        sta TP+1
        ldy TLEN
        cpy #2
        bcc @no
        dey
        dey
        lda (TP),y
        cmp #'/'
        bne @no
        iny
        lda (TP),y
        and #$DF                ; upper case
        cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcs @no
        sta IKEY,x
        dey
        lda #0                  ; the "/X" is not shown
        sta (TP),y
        dec TLEN
        dec TLEN
@no:    rts

; Copies the next string from port B to QP (with its 0); Y = its length,
; Z set if empty. Stops at the end of MTEXT.
getstr: ldy #0
@l:     tya                     ; room for this byte and the 0 after it?
        sec
        adc QP
        lda QP+1
        adc #0
        cmp #>MTEXTEND
        bcs @full
        lda PBDATA
        sta (QP),y
        beq @e
        iny
        bne @l
@full:  lda PBDATA               ; the rest of the string: skipped
        bne @full
        lda QP+1                ; (none at all: nothing written)
        cmp #>MTEXTEND
        bcs @e
        lda #0
        sta (QP),y
@e:     sty T2                  ; (Y and the Z flag for the caller)
        cpy #0
        rts

; QP moves past the string just copied (T2 + 1)
advance:
        lda QP
        sec
        adc T2
        sta QP
        bcc @r
        inc QP+1
@r:     rts

; Title positions: from x = 8, each title " title " wide
layout: LDW T0, 8
        ldx #0
@l:     cpx NMENU
        beq @e
        lda T0
        sta MXL,x
        lda T0+1
        sta MXH,x
        jsr titlelen            ; + (length + 2) * 8
        clc
        adc #2
        asl
        asl
        asl
        bcc @a
        inc T0+1
@a:     clc
        adc T0
        sta T0
        bcc @n
        inc T0+1
@n:     inx
        bne @l
@e:     rts

; A = length of menu X's title (TP = it)
titlelen:
        lda MTL,x
        sta TP
        lda MTH,x
        sta TP+1
        txa
        pha
        jsr strlen
        sta TMPC
        pla
        tax
        lda TMPC
        rts

; The menu bar with the titles
m_drawbar:
        jsr clipfull
        lda #0
        sta RX0
        sta RX0+1
        sta RY0
        sta RY0+1
        sta RY1+1
        LDW RX1, 639
        lda #MENUH - 1
        sta RY1
        lda #0
        jsr fillrect
        lda #MENUH
        sta RY0
        sta RY1
        lda #1
        jsr fillrect
        lda #0
        sta STYLE
        ldx #0
@t:     cpx NMENU
        beq @e
        stx TMPB
        lda MXL,x
        clc
        adc #8
        sta T0
        lda MXH,x
        adc #0
        sta T0+1
        LDW T1, 1
        jsr moveto
        ldx TMPB
        jsr titlelen
        jsr drawstr
        ldx TMPB
        inx
        bne @t
@e:     clc
        rts

; MENUITEM: X = menu, Y = item, r0 = 0 disable / 1 enable
m_item: cpx NMENU
        bcs @r
        tya
        clc
        adc MFIRST,x
        tax
        lda IFLAG,x
        and #2
        bne @r                  ; separators stay as they are
        lda r0
        and #1
        sta IFLAG,x
@r:     clc
        rts

; Ctrl+letter A (1-26): an enabled item with that shortcut? -> carry set,
; X = menu, Y = item; else carry clear and A kept
m_key:  sta TMPB
        clc
        adc #'A' - 1
        sta TMPC
        ldx #0
@m:     cpx NMENU
        beq @no
        ldy #0
@i:     tya
        cmp MCOUNT,x
        beq @nm
        clc
        adc MFIRST,x
        stx T2
        tax
        lda IKEY,x
        cmp TMPC
        bne @ni
        lda IFLAG,x
        and #1
        beq @ni
        ldx T2
        sec
        rts
@ni:    ldx T2
        iny
        bne @i
@nm:    inx
        bne @m
@no:    lda TMPB
        clc
        rts

; --- menu tracking: the left button went down in the menu bar --------------------------
m_track:
        jsr clipfull            ; (the bar is outside every window: with the
                                ; program's port clip still set, the title
                                ; was not inverted on opening but was on
                                ; closing, and stayed black)
        lda #$FF
        sta CURM
        sta CURI
@loop:  jsr readmouse
        lda MY+1
        bne @notbar
        lda MY
        cmp #MENUH + 1
        bcs @notbar
        jsr titleat             ; X = title under the mouse, or $FF
        bmi @chk
        cpx CURM
        beq @chk
        stx TMPB
        jsr closemenu
        ldx TMPB
        jsr openmenu
        jmp @chk
@notbar:
        lda CURM
        bmi @chk
        jsr menubox
        jsr inrect
        bcc @out
        lda MY                  ; item = (MY - top - 2) / 16
        sec
        sbc RY0
        sta T0
        lda MY+1
        sbc RY0+1
        sta T0+1
        SUBW T0, T0, 2
        bmi @out
        ldx #4
@sh:    lsr T0+1
        ror T0
        dex
        bne @sh
        lda T0
        ldx CURM
        cmp MCOUNT,x
        bcs @out
        sta TMPB
        clc
        adc MFIRST,x
        tax
        lda IFLAG,x
        and #1
        beq @out
        lda TMPB
        cmp CURI
        beq @chk
        jsr hiitem              ; off the old one
        lda TMPB
        sta CURI
        jsr hiitem              ; on the new one
        jmp @chk
@out:   jsr hiitem
        lda #$FF
        sta CURI
@chk:   lda BUTTONS
        and #1
        beq @up
        jsr waitframe
        jmp @loop
@up:    lda CURI
        sta SELI
        lda CURM
        sta SELM
        jsr flash               ; the chosen item blinks
        jsr closemenu
        lda CLICKS
        ldx SELM
        bmi @none
        ldy SELI
        cpy #$FF
        beq @none
        sec
        rts
@none:  clc
        rts

; X = menu whose title is under MX ($FF if none)
titleat:
        ldx NMENU
@l:     dex
        bmi @r
        lda MX                  ; MX >= MXL/MXH ?
        cmp MXL,x
        lda MX+1
        sbc MXH,x
        bcs @f
        bcc @l
@f:     txa                     ; (N clear: found)
@r:     rts

; RX0..RY1 = the box of menu CURM
menubox:
        ldx CURM
        lda MXL,x
        sta RX0
        lda MXH,x
        sta RX0+1
        LDW RY0, MENUH
        lda MWIDTH,x            ; width * 8 + 8
        asl
        asl
        asl
        sta T0
        lda #0
        rol
        sta T0+1
        lda RX0
        clc
        adc T0
        sta RX1
        lda RX0+1
        adc T0+1
        sta RX1+1
        ADDW RX1, RX1, 8
        lda MCOUNT,x            ; height: count * 16 + 4
        asl
        asl
        asl
        asl
        clc
        adc #MENUH + 4
        sta RY1
        lda #0
        adc #0
        sta RY1+1
        lda RX1+1               ; keep it on the screen
        cmp #>637
        bcc @ok
        lda RX1
        cmp #<637
        bcc @ok
        lda RX1                 ; shift left by RX1 - 637
        sec
        sbc #<637
        sta T0
        lda RX1+1
        sbc #>637
        sta T0+1
        lda RX0
        sec
        sbc T0
        sta RX0
        lda RX0+1
        sbc T0+1
        sta RX0+1
        LDW RX1, 637
@ok:    rts

; Opens menu X: title inverted, box drawn (what was under it saved)
openmenu:
        stx CURM
        lda #$FF
        sta CURI
        jsr titlerect
        jsr invrect
        jsr menubox
        jsr shadowed
        jsr saveunder
        jsr menubox
        jsr boxdraw
        ldx CURM                ; the items
        lda #0
        sta TMPC
@i:     ldx CURM
        lda TMPC
        cmp MCOUNT,x
        beq @e
        jsr drawitem
        inc TMPC
        bne @i
@e:     rts

; RX1, RY1 += 2 (the shadow)
shadowed:
        ADDW RX1, RX1, 2
        ADDW RY1, RY1, 2
        rts

; Box RX0..RY1 with a shadow: white, framed
boxdraw:
        jsr shadowed
        ADDW RX0, RX0, 2
        ADDW RY0, RY0, 2
        lda #1
        jsr fillrect
        SUBW RX0, RX0, 2
        SUBW RY0, RY0, 2
        SUBW RX1, RX1, 2
        SUBW RY1, RY1, 2
        lda #0
        jsr fillrect
        jmp framerect

; Item TMPC of menu CURM
drawitem:
        jsr menubox
        lda TMPC
        asl
        asl
        asl
        asl
        clc
        adc #MENUH + 2
        sta T1
        lda #0
        sta T1+1
        ldx CURM
        lda TMPC
        clc
        adc MFIRST,x
        tax
        stx T2
        lda IFLAG,x
        and #2
        beq @text
        lda T1                  ; separator: a grey line across
        clc
        adc #8
        sta RY0
        sta RY1
        lda #0
        sta RY0+1
        sta RY1+1
        ADDW RX0, RX0, 1
        SUBW RX1, RX1, 1
        jmp patrect
@text:  ADDW T0, RX0, 8
        jsr moveto
        lda #0
        sta STYLE
        lda #R_SET
        sta ROP
        ldx T2
        lda IPL,x
        sta TP
        lda IPH,x
        sta TP+1
        jsr drawstr
        ldx T2
        lda IKEY,x              ; "^X" at the right
        beq @dim
        SUBW T0, RX1, 24
        jsr moveto
        lda #'^'
        sta CHOUT
        ldx T2
        lda IKEY,x
        sta CHOUT
@dim:   ldx T2
        lda IFLAG,x
        and #1
        bne @r
        ADDW RX0, RX0, 1        ; disabled: half the ink taken out
        SUBW RX1, RX1, 1
        MOVW RY0, T1
        ADDW RY1, T1, 15
        lda #5                  ; CLEAR where the pattern is 1
        sta ROP
        lda #1
        sta PATON
        jsr setrect
        lda #C_BOXF
        sta BCMD
        lda #0
        sta PATON
        lda #R_SET
        sta ROP
@r:     rts

; Inverts item CURI (if any) of menu CURM
hiitem: lda CURI
        bmi @r
        jsr menubox
        lda CURI
        asl
        asl
        asl
        asl
        clc
        adc #MENUH + 2
        sta RY0
        lda #0
        sta RY0+1
        ADDW RY1, RY0, 15
        ADDW RX0, RX0, 1
        SUBW RX1, RX1, 1
        jmp invrect
@r:     rts

; The chosen item blinks twice
flash:  lda CURI
        bmi @r
        ldx #4
@f:     txa
        pha
        jsr hiitem
        ldy #4
@w:     jsr waitframe
        dey
        bne @w
        pla
        tax
        dex
        bne @f
@r:     rts

; Closes menu CURM: what was under it back, title normal again
closemenu:
        lda CURM
        bmi @r
        jsr menubox
        jsr shadowed
        jsr restunder
        ldx CURM
        jsr titlerect
        jsr invrect
        lda #$FF
        sta CURM
        sta CURI
@r:     rts

; RX0..RY1 = title X in the bar
titlerect:
        lda MXL,x
        sta RX0
        lda MXH,x
        sta RX0+1
        jsr titlelen
        clc
        adc #2
        asl
        asl
        asl
        sta T0
        lda #0
        rol
        sta T0+1
        lda RX0
        clc
        adc T0
        sta RX1
        lda RX0+1
        adc T0+1
        sta RX1+1
        SUBW RX1, RX1, 1
        lda #0
        sta RY0
        sta RY0+1
        sta RY1+1
        lda #MENUH - 1
        sta RY1
        rts

; --- dialogs ---------------------------------------------------------------------------------

; ALERT: r0 = message (lines separated by CR), r1 = buttons "OK|Cancel"
; (0 = just OK). Returns A = the button chosen (Enter = the first, Esc = the
; last).
d_alert:
        lda #0
        sta ASKING
        jsr dlgtext
        jsr dlgopen
        jmp dlgloop

; ASK: r0 = prompt, r1 = the caller's buffer (its text is shown first),
; r2 = maximum length (1-40). Carry clear: OK, the buffer has the answer.
d_ask:  lda #1
        sta ASKING
        lda r2
        beq @m
        cmp #41
        bcc @ok
@m:     lda #40
@ok:    sta ASKMAX
        MOVW T0, r1             ; the current text
        LDW QP, ASKBUF
        lda ASKMAX
        jsr fetchstr
        jsr dlgtext
        lda #<okcancel          ; buttons OK and Cancel
        sta TP
        lda #>okcancel
        sta TP+1
        ldy #0
@b:     lda (TP),y
        sta STRBUF2,y
        beq @bd
        iny
        bne @b
@bd:    jsr splitbtn
        jsr dlgopen
        jsr drawfield
        jsr dlgloop
        cmp #0
        bne @cancel
        MOVW T0, r1             ; OK: the answer to the caller's buffer
        jsr farptr
        ldy #0
@s:     lda ASKBUF,y
        sta PBDATA
        beq @sd
        iny
        bne @s
@sd:    lda #0
        clc
        rts
@cancel:
        lda #1
        sec
        rts
okcancel: .byte "OK|Cancel", 0

; Copies the message (r0) and the buttons (r1) and measures them
dlgtext:
        MOVW T0, r0
        LDW QP, STRBUF
        lda #250
        jsr fetchstr
        lda ASKING
        bne @lines
        lda r1                  ; buttons
        ora r1+1
        bne @b
        lda #'O'
        sta STRBUF2
        lda #'K'
        sta STRBUF2+1
        lda #0
        sta STRBUF2+2
        beq @s
@b:     MOVW T0, r1
        LDW QP, STRBUF2
        lda #60
        jsr fetchstr
@s:     jsr splitbtn
@lines: lda #1                  ; lines and the longest one
        sta NLINES
        lda #0
        sta MAXLEN
        sta TMPB
        ldy #0
@l:     lda STRBUF,y
        beq @end
        cmp #13
        bne @c
        inc NLINES
        lda #0
        sta TMPB
        beq @n
@c:     inc TMPB
        lda TMPB
        cmp MAXLEN
        bcc @n
        sta MAXLEN
@n:     iny
        bne @l
@end:   rts

; Buttons "A|B|C" in STRBUF2 -> NBTN, BOFS (start of each), BLEN
splitbtn:
        lda #0
        sta NBTN
        ldy #0
@b:     ldx NBTN
        tya
        sta BOFS,x
        lda #0
        sta BLEN,x
@c:     lda STRBUF2,y
        beq @last
        cmp #'|'
        beq @next
        inc BLEN,x
        iny
        bne @c
@next:  lda #0
        sta STRBUF2,y
        iny
        inc NBTN
        lda NBTN
        cmp #3
        bne @b
        rts
@last:  inc NBTN
        rts

; Size, place, save under, draw: box, message, buttons
dlgopen:
        lda #0                  ; buttons' total width: sum((len+4)*8) + 16 per gap
        sta BTOT
        sta BTOT+1
        ldx #0
@w:     lda BLEN,x
        clc
        adc #4
        asl
        asl
        asl
        sta BW,x
        clc
        adc BTOT
        sta BTOT
        bcc @w1
        inc BTOT+1
@w1:    inx
        cpx NBTN
        bne @w
        dex
        txa
        asl
        asl
        asl
        asl
        clc
        adc BTOT
        sta BTOT
        bcc @w2
        inc BTOT+1
@w2:    lda MAXLEN              ; width = max(text * 8 + 48, buttons + 48, 240)
        ldx ASKING
        beq @a
        lda ASKMAX
        cmp MAXLEN
        bcs @a
        lda MAXLEN
@a:     sta T0
        lda #0
        sta T0+1
        asl T0
        rol T0+1
        asl T0
        rol T0+1
        asl T0
        rol T0+1
        ADDW T0, T0, 48
        ADDW T1, BTOT, 48
        lda T1                  ; T0 = max(T0, T1)
        cmp T0
        lda T1+1
        sbc T0+1
        bcc @m1
        MOVW T0, T1
@m1:    lda T0+1
        bne @m2
        lda T0
        cmp #240
        bcs @m2
        LDW T0, 240
@m2:    MOVW DLGW, T0
        lda NLINES              ; height = lines * 16 + 76 (+ 28 for a field)
        asl
        asl
        asl
        asl
        clc
        adc #76
        ldx ASKING
        beq @h
        adc #28
@h:     sta DLGH
        LDW T1, 640             ; x0 = (640 - W) / 2
        lda T1
        sec
        sbc DLGW
        sta T1
        lda T1+1
        sbc DLGW+1
        lsr
        sta RX0+1
        lda T1
        ror
        sta RX0
        lda RX0                 ; x1 = x0 + W - 1
        clc
        adc DLGW
        sta RX1
        lda RX0+1
        adc DLGW+1
        sta RX1+1
        SUBW RX1, RX1, 1
        lda #<396               ; y0 = (396 - H) / 2
        sec
        sbc DLGH
        sta T1
        lda #>396
        sbc #0
        lsr
        sta RY0+1
        lda T1
        ror
        sta RY0
        lda RY0
        clc
        adc DLGH
        sta RY1
        lda RY0+1
        adc #0
        sta RY1+1
        ldx #7
@k:     lda RX0,x
        sta DLGR,x
        dex
        bpl @k
        jsr clipfull
        jsr shadowed            ; save what is under it (with the shadow)
        jsr saveunder
        jsr dlgrect
        jsr boxdraw             ; box, an inner frame
        jsr dlgrect
        ADDW RX0, RX0, 3
        ADDW RY0, RY0, 3
        SUBW RX1, RX1, 3
        SUBW RY1, RY1, 3
        jsr framerect
        jsr dlgrect             ; the message, line by line
        ADDW T0, RX0, 24
        ADDW T1, RY0, 20
        jsr moveto
        lda #0
        sta STYLE
        ldy #0
@t:     lda STRBUF,y
        beq @bt
        cmp #13
        bne @ch
        ADDW T1, T1, 16
        jsr moveto
        jmp @nx
@ch:    sta CHOUT
@nx:    iny
        bne @t
@bt:    lda DLGR+6              ; buttons, right-aligned near the bottom
        sec
        sbc #36
        sta BY
        lda DLGR+7
        sbc #0
        sta BY+1
        lda DLGR+4              ; first x = x1 - 24 - total
        sec
        sbc #24
        sta T0
        lda DLGR+5
        sbc #0
        sta T0+1
        lda T0
        sec
        sbc BTOT
        sta T0
        lda T0+1
        sbc BTOT+1
        sta T0+1
        ldx #0
@bb:    lda T0                  ; positions first
        sta BXL,x
        lda T0+1
        sta BXH,x
        lda T0                  ; next: + width + 16
        clc
        adc BW,x
        sta T0
        bcc @b1
        inc T0+1
@b1:    ADDW T0, T0, 16
        inx
        cpx NBTN
        bne @bb
        lda #0                  ; then the buttons
        sta BI
@bd:    ldx BI
        jsr drawbtn
        inc BI
        lda BI
        cmp NBTN
        bne @bd
        rts

; RX0..RY1 = the dialog box
dlgrect:
        ldx #7
@c:     lda DLGR,x
        sta RX0,x
        dex
        bpl @c
        rts

; RX0..RY1 = button X
btnrect:
        lda BXL,x
        sta RX0
        lda BXH,x
        sta RX0+1
        lda BW,x
        clc
        adc RX0
        sta RX1
        lda RX0+1
        adc #0
        sta RX1+1
        SUBW RX1, RX1, 1
        MOVW RY0, BY
        ADDW RY1, BY, 21
        rts

; Button X: frame, label centred; the first one has a thick frame
drawbtn:
        stx T2
        jsr btnrect
        lda #0
        jsr fillrect
        jsr framerect
        ldx T2
        bne @lab
        SUBW RX0, RX0, 3        ; the default button
        SUBW RY0, RY0, 3
        ADDW RX1, RX1, 3
        ADDW RY1, RY1, 3
        jsr framerect
        ADDW RX0, RX0, 1
        ADDW RY0, RY0, 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        jsr framerect
@lab:   ldx T2
        jsr btnrect
        ldx T2
        lda BLEN,x
        jsr centrex
        ADDW T1, RY0, 3
        jsr moveto
        ldx T2
        lda BOFS,x
        clc
        adc #<STRBUF2
        sta TP
        lda #>STRBUF2
        adc #0
        sta TP+1
        lda #0
        sta STYLE
        jmp drawstr

; The text field of ASK: its box, the text and a cursor
drawfield:
        jsr fieldrect
        lda #0
        jsr fillrect
        jsr framerect
        jsr fieldrect
        ADDW T0, RX0, 4
        ADDW T1, RY0, 3
        jsr moveto
        lda #0
        sta STYLE
        LDW TP, ASKBUF
        jsr drawstr
        lda #'_'
        sta CHOUT
        rts

fieldrect:
        jsr dlgrect
        ADDW RX0, RX0, 20
        SUBW RX1, RX1, 20
        lda NLINES
        asl
        asl
        asl
        asl
        clc
        adc #24
        adc RY0
        sta RY0
        lda RY0+1
        adc #0
        sta RY0+1
        ADDW RY1, RY0, 21
        rts

; Waits for a button: Enter = the first, Esc = the last, or a click on one
; (inverted while the button is held over it). Then closes the dialog.
; ASK: typing edits ASKBUF. -> A = button.
dlgloop:
        lda CLICKS
@loop:  jsr waitframe
        lda KBDCR
        bpl @mouse
        lda KBD
        and #$7F
        cmp #13
        bne @esc
        lda #0
        jmp @done
@esc:   cmp #27
        bne @type
        ldx NBTN
        dex
        txa
        jmp @done
@type:  ldx ASKING
        beq @loop
        cmp #8                  ; Backspace (and Delete) erase
        beq @bs
        cmp #127
        beq @bs
        cmp #' '
        bcc @loop
        ldy #0
@len:   ldx ASKBUF,y
        beq @add
        iny
        bne @len
@add:   cpy ASKMAX
        bcs @loop
        sta ASKBUF,y
        lda #0
        sta ASKBUF+1,y
        jsr drawfield
        jmp @loop
@bs:    ldy #0
@l2:    lda ASKBUF,y
        beq @del
        iny
        bne @l2
@del:   cpy #0
        beq @loop
        lda #0
        sta ASKBUF-1,y
        jsr drawfield
        jmp @loop
@mouse: lda CLICKS
        and #1
        beq @loop
        jsr readmouse
        ldx #0
@hit:   stx TMPB
        jsr btnrect
        jsr inrect
        bcs @press
        ldx TMPB
        inx
        cpx NBTN
        bne @hit
        jmp @loop
@press: lda #1                  ; held: inverted while over it
        sta INV
        jsr invbtn
@hold:  jsr waitframe
        jsr readmouse
        ldx TMPB
        jsr btnrect
        jsr inrect
        lda #0
        rol                     ; 1 if over it
        cmp INV
        beq @same
        sta INV
        jsr invbtn
@same:  lda BUTTONS
        and #1
        bne @hold
        lda INV
        bne @chose
        jmp @loop               ; released outside: nothing
@chose:
        jsr invbtn
        lda TMPB
@done:  pha
        jsr dlgrect             ; what was under the dialog back
        jsr shadowed
        jsr restunder
        lda CLICKS
        pla
        clc
        rts

invbtn: ldx TMPB
        jsr btnrect
        ADDW RX0, RX0, 1
        ADDW RY0, RY0, 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        jmp invrect

        .include "common.inc"

; --- this bank's variables ----------------------------------------------------------
NITEM:  .res 1
TLEN:   .res 1
CURM:   .res 1
CURI:   .res 1
SELM:   .res 1
SELI:   .res 1
ASKING: .res 1
ASKMAX: .res 1
NLINES: .res 1
MAXLEN: .res 1
NBTN:   .res 1
BOFS:   .res 3
BLEN:   .res 3
BW:     .res 3
BXL:    .res 3
BXH:    .res 3
BY:     .res 2
BTOT:   .res 2
DLGW:   .res 2
DLGH:   .res 1
DLGR:   .res 8
INV:    .res 1
BI:     .res 1
