;=============================================================================
; mini6502_basic.asm - EhBASIC for mini6502                    (RAM $A000-$CFFF)
;-----------------------------------------------------------------------------
; Derived from EhBASIC. EhBASIC is (c) Lee Davison, free for personal,
; non-commercial use; see README.txt. mini6502 additions (this file, the
; "!" extension wedge and API, and the extensions in ../basicx) Copyright
; (C) 2026 Benoit Colson, with the help of Claude AI, under the same
; EhBASIC terms.
; This file is the mini6502 glue: start-up, keyboard and terminal routines.
; The interpreter itself is ehbasic.asm.
;
; Start it from the monitor:
;   A000R   cold start: clears the screen, uses all of $0400-$9FFF (39935 bytes)
;   A003R   warm start: back to BASIC with the program kept (after F1 / RESET)
;   SYSTEM  (in BASIC) goes back to the monitor; G (or A003R) returns
;
; Disk (the "disk" folder next to mini6502, shared with the monitor):
;   SAVE "NAME"     saves the program
;   LOAD "NAME"     loads a program saved by SAVE (wherever BASIC's program
;                   memory starts), clears the variables, back to Ready
;   DIR or CAT      lists the disk (CALL $A006 does the same)
;   KILL "NAME"     deletes a file
;
; DESKTOP and EDIT are constants like PI: CALL DESKTOP ($CC90), CALL EDIT
; ($CC18, far-call entry 2: the editor with its text kept).
; CLS clears the screen (with the current COLOR) and homes the cursor.
; LOCATE row[,column] moves the cursor (1-25, 1-80, as in QBasic); the next
; PRINT starts there. Without a column the cursor stays in its column.
;   The name can be any string expression: SAVE N$, LOAD "GAME"+STR$(I)...
;
; Extensions (wedge): a statement that starts with "!" is an extension
; command, and "!" in an expression an extension function (X=!MOUSEX),
; handled by an extension in banks $00-$07 (see basicx/README.txt):
; a bank whose $E000 starts with "BX". BASIC finds them at every cold or
; warm start (SYSTEM, L GFX E000 00, G installs one). The jump table below
; ($A009-$A038) is what extensions call; it stays at these addresses.
;
; Memory used: $00-$EF zero page except $E2-$EE ($F0-$FF are left to the
; extensions), $0100 stack, $0300-$036F
; (BASIC variables, vectors and input line), $0400-$9FFF program and data.
; The monitor keeps $E6-$ED and $0200-$0287, so you can go back and forth.
;=============================================================================

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

MONITOR = $FF1F         ; the monitor's prompt (Woz Monitor GETLINE address)
ECHO    = $FFEF         ; the monitor's character output (keeps A, X, Y)

SAVCOL  = $030E         ; COLOR before the sign-on message (in the unused
                        ; IRQ/NMI code space after VEC_SV)
BGCOL   = $030F         ; its background nibble
XMASK   = $0310         ; extensions: bit N = an extension in bank N
XBANK   = $0311         ; the bank selected when the "!" statement began
XIN     = $0312         ; nonzero while an extension runs
XTRY    = $0313         ; banks still to ask
XSAVB   = $0314         ; (XDISK)
XNUM    = $0315         ; the extension being asked
XVEC    = $0316         ; 2: its entry

        .org $A000

        jmp cold                ; $A000
        jmp warm                ; $A003
        jmp dir                 ; $A006: CALL $A006 lists the disk
; --- the extension API ($A009...): fixed addresses, see basicx/bx.inc ---------
        jmp LAB_IGBY            ; $A009 XCHRGET  next character (A; Z at the end)
        jmp LAB_GBYT            ; $A00C XCHRGOT  this character again
        jmp LAB_GTBY            ; $A00F XGETBYTE a 0-255 expression: X
        jmp LAB_1C01            ; $A012 XCOMMA   a "," or Syntax error
        jmp xgetword            ; $A015 XGETWORD an expression: Itempl/h (16 bits)
        jmp xgetstr             ; $A018 XGETSTR  a string: A = length, X/Y = address
        jmp xgetvar             ; $A01B XGETVAR  a numeric variable to set (XSETVAR)
        jmp xsetvar             ; $A01E XSETVAR  it = Y/A (Y low, A high, signed)
        jmp xerror              ; $A021 XERROR   error X (BASIC's codes), Ready
        .word LAB_KEYT          ; $A024 XKEYT    BASIC's keyword table (for bxmatch.inc)
        .byte 0
        jmp xdisk               ; $A027 XDISK    disk command A with bank X selected
        jmp LAB_PRNA            ; $A02A XPRINT   print the character A
        jmp LAB_CRLF            ; $A02D XCRLF    new line
        jmp LAB_EVNM            ; $A030 XGETNUM  a numeric expression: FAC1
        jmp LAB_SNER            ; $A033 XSYNTAX  Syntax error
        jmp LAB_FCER            ; $A036 XFUNC    Function call error (a bad value)

; the interpreter first, so the glue below can use its zero page names
        .include "ehbasic.asm"

; --- start-up ------------------------------------------------------------------
cold:
        cld
        ldx #$FF
        txs
        jsr setvec
        lda #2                  ; clear the screen (current COLOR), cursor home
        sta SYSCTL

; sign-on message in rainbow colours: each visible character gets the next
; character colour 1-15 (black is skipped, and so is the colour of the
; background, which would hide it); the background is kept, and after the
; message the characters are light grey (7)
        lda COLOR
        sta SAVCOL
        and #$F0
        sta BGCOL
        ldx #0                  ; last colour used
        ldy #0
@msg:   lda signon,y
        beq @end
        cmp #'!'                ; spaces and control codes: no colour change
        bcc @out
        pha
@pick:  inx                     ; next colour, 1-15
        cpx #16
        bcc @chk
        ldx #1
@chk:   txa
        asl
        asl
        asl
        asl
        cmp BGCOL               ; same as the background?
        beq @pick               ; then it would be invisible: skip it
        txa
        ora BGCOL
        sta COLOR
        pla
@out:   jsr outch
        iny
        bne @msg
@end:   lda BGCOL               ; light grey characters on the same background
        cmp #$70                ; unless the background is light grey itself:
        beq @keep               ; then keep the colour we started with
        ora #$07
        bne @set
@keep:  lda SAVCOL
@set:   sta COLOR
        jmp LAB_COLD

warm:
        cld
        ldx #$FF
        txs
        lda LAB_WARM            ; set up by a cold start: JMP opcode
        cmp #$4C
        bne cold                ; never cold-started: do it now
        jsr setvec
        jmp LAB_WARM

; Copies the I/O vectors to page 3 (VEC_IN, VEC_OUT, VEC_LD, VEC_SV) and
; tells the monitor that G comes back to the warm start
setvec:
        lda #<warm
        sta WARMLO
        lda #>warm
        sta WARMHI
        ldy #vecs_end - vecs
@copy:  lda vecs-1,y
        sta VEC_IN-1,y
        dey
        bne @copy
; the extensions: banks $00-$07 starting with "BX"; each one's INIT is called
        lda #0
        sta XMASK
        sta XIN
        lda BANK
        pha
        ldx #7
@x:     stx BANK
        lda $E000
        cmp #'B'
        bne @no
        lda $E001
        cmp #'X'
        bne @no
        stx XNUM
        jsr $E006               ; its INIT
        ldx XNUM
        stx BANK
        lda bits,x
        ora XMASK
        sta XMASK
@no:    dex
        bpl @x
        pla
        sta BANK
        rts
bits:   .byte 1, 2, 4, 8, 16, 32, 64, 128

vecs:
        .word inch              ; VEC_IN
        .word outch             ; VEC_OUT
        .word bload             ; VEC_LD
        .word bsave             ; VEC_SV
vecs_end:

; --- I/O -----------------------------------------------------------------------

; Key if one is waiting: carry set and the key in A; else carry clear.
; Delete becomes Backspace, which EhBASIC understands.
inch:
        lda KBDCR
        bpl @none
        lda KBD
        and #$7F
        cmp #$7F
        bne @key
        lda #$08
@key:   cmp #0                  ; carry set (a key) and Z set for a NUL, which
        rts                     ; BASIC then ignores (extended keys: arrows...)
@none:  clc
        rts

; Ctrl-C check, called by BASIC between statements. EhBASIC's own CTRLC
; reads (and loses) any key typed while a program runs; this one only looks
; at the waiting key (KBDPEEK) and takes it only if it is Ctrl-C, so typing
; ahead and pasting work, even across SYSTEM.
mini_cc:
        lda ccflag              ; Ctrl-C checking switched off?
        bne @done
        lda KBDPEEK
        and #$7F                ; 0 if no key
        cmp #$03
        bne @done
        lda KBD                 ; take the Ctrl-C
        lda #$03
        jmp LAB_1636            ; BASIC's STOP/break handling
@done:  jmp LAB_FBA2            ; the rest of CTRLC: interrupt checks

; Prints A; A, X and Y are kept. Goes through the monitor's ECHO so the
; monitor knows where the cursor is when SYSTEM goes back to it.
outch:
        jmp ECHO

; --- disk --------------------------------------------------------------------

; Evaluates the string after LOAD/SAVE and makes it the disk file name
getname:
        jsr LAB_EVEX            ; evaluate expression
        jsr LAB_EVST            ; must be a string: A = length, YX = address
        sta DNLEN
        stx DNAME
        sty DNAME+1
        rts

; SAVE "NAME": the program, from the start of BASIC memory to the variables
bsave:
        jsr getname
        lda Smeml
        sta DSTART
        lda Smemh
        sta DSTART+1
        lda Svarl
        sta DEND
        lda Svarh
        sta DEND+1
        lda #2
        sta DCMD
        jsr dcheck              ; error message and Ready if it failed
        rts

; LOAD "NAME": into BASIC memory, then the lines are re-linked, the variables
; cleared and BASIC waits at Ready (a running program stops)
bload:
        jsr getname
        lda Smeml
        sta DSTART
        lda Smemh
        sta DSTART+1
        lda Ememl               ; must fit below the top of BASIC memory
        sta DEND
        lda Ememh
        sta DEND+1
        lda #3                  ; load at DSTART
        sta DCMD
        jsr dcheck              ; error message and Ready if it failed
        lda DEND                ; the variables start after the program
        sta Svarl
        lda DEND+1
        sta Svarh
        lda #<LAB_RMSG          ; "Ready"
        ldy #>LAB_RMSG
        jsr LAB_18C3
        jmp LAB_1319            ; clear variables, re-link lines, wait for input

; DIR / CAT (and CALL $A006): the host lists the disk on the terminal
mini_dir:
        beq dir                 ; nothing may follow DIR / CAT
        jmp LAB_SNER            ; "Syntax Error"
dir:
        lda #4
        sta DCMD
        lda #0                  ; the cursor is at the start of a line
        sta TPos
        rts

; LOCATE row[,column]: move the cursor, 1-based like QBasic (0 counts as 1)
mini_locate:
        jsr LAB_GTBY            ; row -> X, A = the character after it
        cpx #0
        beq @r0
        dex
@r0:    stx CURY
        cmp #','                ; a column too?
        bne @done
        jsr LAB_1C01            ; skip the ","
        jsr LAB_GTBY            ; column -> X
        txa
        beq @c0
        dex
@c0:    stx CURX
@done:  lda CURX                ; BASIC's own idea of the column (for TAB,
        sta TPos                ; commas and line wrapping)
        rts

; SYSTEM: back to the monitor (A003R comes back with the program kept)
mini_system:
        beq @go                 ; nothing may follow SYSTEM
        jmp LAB_SNER            ; "Syntax Error"
@go:    jmp MONITOR

; KILL "NAME": delete a file
mini_kill:
        jsr getname
        lda #5
        sta DCMD
        jsr dcheck              ; error message and Ready if it failed
        rts

; CLS: the host clears the screen
mini_cls:
        beq @go                 ; nothing may follow CLS
        jmp LAB_SNER            ; "Syntax Error"
@go:    lda #2
        sta SYSCTL
        lda #0                  ; cursor at the start of a line
        sta TPos
        rts

; Constants DESKTOP and EDIT (like PI): CALL DESKTOP, CALL EDIT. They are
; far-call table entries 17 (the desktop) and 2 (the editor, text kept)
mini_desktop:
        lda #<c_desktop
        ldy #>c_desktop
        jmp LAB_UFAC
mini_edit:
        lda #<c_edit
        ldy #>c_edit
        jmp LAB_UFAC
c_desktop: .byte $90, $4C, $90, $00     ; 52368 = $CC90
c_edit:    .byte $90, $4C, $18, $00     ; 52248 = $CC18

; Returns if the disk command worked, else reports it (the stack is reset)
dcheck:
        lda DSTAT
        bne diskerr
        rts

; Disk error: "?File not found Error" (plus " in line N"), then Ready
diskerr:
        tax
        dex
        cpx #6
        bcc @known
        ldx #3                  ; anything else: "File"
@known: lda errlo,x
        pha
        lda errhi,x
        pha
        jsr LAB_CRLF
        pla
        tay
        pla
        jsr LAB_18C3            ; print the message
        jsr LAB_1491            ; flush the stack
        lda #<LAB_EMSG          ; " Error" ...
        ldy #>LAB_EMSG
        jmp LAB_1269            ; ... " in line N", Ready

errlo:  .byte <e1, <e2, <e3, <e4, <e5, <e6
errhi:  .byte >e1, >e2, >e3, >e4, >e5, >e6
e1:     .byte "File not found", 0
e2:     .byte "Bad file name", 0
e3:     .byte "Program too big", 0
e4:     .byte "File", 0
e5:     .byte "Disk command", 0
e6:     .byte "Bad range", 0

; --- extensions ----------------------------------------------------------------

; A statement that is not a keyword: "!" + an extension command, else LET
mini_stmt:
        ldy #0
        lda (Bpntrl),y
        cmp #'!'
        beq @x
        jmp LAB_LET
@x:     ldy #<$E003             ; the extensions' statement entry
        bne xcall

; "!" in an expression (from LAB_GVAL): a function; its value (Y low, A high,
; signed) goes into FAC1
mini_func:
        ldy #<$E009             ; the extensions' function entry
        jsr xcall
        jmp LAB_AYFC

; Asks each extension in turn (entry $E0yy, Y = yy) until one takes the "!"
; command: carry clear. Nested calls (a function inside an extension's
; statement) keep the program's bank in XBANK.
xcall:  sty XVEC
        lda #$E0
        sta XVEC+1
        jsr LAB_IGBY            ; past the "!"
        lda BANK
        pha
        ldx XIN
        bne @in
        sta XBANK
@in:    inc XIN
        lda XMASK
        sta XTRY
        ldx #0
@ask:   lsr XTRY
        bcc @next
        stx XNUM
        stx BANK
        jsr @go
        ldx XNUM
        bcc @done
@next:  inx
        cpx #8
        bne @ask
        ldx #$02                ; nobody knows it: Syntax error
        jmp LAB_XERR
@go:    jmp (XVEC)
@done:  dec XIN
        tax                     ; (a function's value: Y, A)
        pla
        sta BANK
        txa
        rts

; Called by every error: an extension's bank is replaced by the program's
mini_xerr:
        lda XIN
        beq @r
        lda XBANK
        sta BANK
        lda #0
        sta XIN
@r:     rts

xerror  = LAB_XERR              ; (mini_xerr puts the bank back)

; XGETWORD: a numeric expression, its 16 bits in Itempl/h
xgetword:
        jsr LAB_EVNM
        jmp LAB_F2FX

; XGETSTR: a string expression: A = length, X/Y = its address
xgetstr:
        jsr LAB_EVEX
        jmp LAB_EVST

; XGETVAR: the numeric variable named here (XSETVAR then sets it)
xgetvar:
        jsr LAB_GVAR
        sta Lvarpl
        sty Lvarph
        lda Dtypef
        bpl @ok
        ldx #$18                ; a string variable: Type mismatch
        jmp LAB_XERR
@ok:    rts

; XSETVAR: that variable = Y (low) A (high), signed
xsetvar:
        jsr LAB_AYFC
        jmp LAB_PFAC

; XDISK: disk command A with bank X at $E000 while it runs (the extension's
; own bank comes back); a failure gives BASIC's disk error message
xdisk:  pha
        lda BANK
        sta XSAVB
        stx BANK
        pla
        sta DCMD
        lda XSAVB
        sta BANK
        lda DSTAT
        beq @ok
        jsr mini_xerr
        lda DSTAT
        jmp diskerr
@ok:    rts

signon:
        .byte "mini6502 BASIC - Derived from EhBASIC", $0D, $00

