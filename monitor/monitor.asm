;=============================================================================
; monitor.asm - the mini6502 system monitor                    (ROM $F000-$FFFF)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; An original monitor for mini6502, written to feel like the
; Woz Monitor (same commands, same entry points) while leaving 4K to grow in.
;
; Build (cc65 suite):  ca65 monitor.asm -o monitor.o -l monitor.lst
;                      ld65 -C monitor.cfg monitor.o -o monitor.bin
;
; Commands (several per line, separated by spaces; hex, upper or lower case)
;   HHHH            show the byte at HHHH
;   HHHH.HHHH       show a range, 8 bytes per line
;   .HHHH           continue showing from the last address up to HHHH
;   HHHH: BB BB ..  store bytes from HHHH on (shows the old byte at HHHH,
;                   except for I/O addresses $Dxxx, where reading can have
;                   an effect: a data port moves on, KBD takes the key);
;                   a 3-4 digit number starts a new address: D020: 05 D021: 1E
;   : BB BB ..      store at the last address shown, or after the last byte stored
;   HHHH R          run the program at HHHH; an RTS comes back to the monitor
;   R               run again at the last address shown
;   S NAME HHHH.HHHH  save HHHH..HHHH (end included) to the file NAME
;   S NAME HHHH.HHHH BB   ... with bank BB at $E000-$EFFF while saving
;   L NAME          load NAME at the address it was saved from
;   L NAME HHHH     load NAME at HHHH
;   L NAME HHHH BB  load NAME at HHHH with bank BB at $E000-$EFFF
;                   (the bank selected before is selected again afterwards)
;   V               list the far-call vector table at $CC00
;   V NN BB HHHH [NAME]  set entry NN (00-27): a call to it runs HHHH in
;                   bank BB; NAME (up to 8 characters) is what VFIND finds
;   M               list the bank map: who owns each bank
;   M BB OO         set bank BB's owner to OO (00 = free it)
;                   after a load, R runs what was loaded
;   $               list the files on the disk
;   K NAME          delete (kill) the file NAME
;   P               show the disk's current folder (path: "/", "/GAMES"...)
;   P NAME          change it: a folder in it, ".." (up), "/" (the top) or
;                   a path "/GAMES/SAVES"; names everywhere are looked up
;                   in it (or given as a path from the top: L /GAMES/X)
;   T NAME          type the text file NAME as if typed on the keyboard: a
;                   script of monitor commands, which can go on into what
;                   it starts (BASIC lines after A000R, for instance)
;   W               wipe: clear the screen (C would be read as hex)
;   X               exit: quits the mini6502 emulator
;   G               go back to the program that set the warm start address
;                   ($D002/$D003, e.g. BASIC after SYSTEM or F1)
;   ?               short help
;   Esc cancels the line, Backspace/Delete erase, Enter executes.
;   S, L and $ use the rest of the line. Files are in the "disk" folder next
;   to mini6502; names are up to 64 of A-Z 0-9 . _ - (typed in upper case).
;
; Boot: at power-on (and after a $FF cold reset, not after F1) the monitor
; loads the disk file BOOT at its own address and runs it, unless keys are
; already waiting (a file typed in from the command line, for instance).
; Without a BOOT file it types BOOT.TXT, if there is one, as a script.
; Save anything as BOOT to start it automatically, e.g. BASIC:
;   L EHBASIC     then     S BOOT A000.CA3C
; If there is no BOOT file the monitor just shows its prompt.
;
; Far calls into banked RAM ($E000-$EFFF, 256 banks of 4K)
;   FARCALL $FFD0 switches to a bank, calls an address there, then switches
;   back to the caller's bank. It takes its target from the 3 bytes after
;   the JSR, so a far call is   JSR $FFD0 / .byte bank / .word address.
;   A, X and Y reach the callee unchanged; on return A, X, Y and the carry
;   are what the callee left. Calls can nest (banked code can far-call too).
;   Uses $E2-$E5 and $EE of the zero page (left free by EhBASIC).
;
;   The system page $CC00-$CFFF (fixed RAM nothing swaps out; see
;   hw/REGISTERS.txt):
;     $CC00  "VT"     signature (written by V)
;     $CC02  count    number of entries in use
;     $CC03-$CC07     reserved
;     $CC08 + 8*NN    entry NN (00-27): JSR $FFD0 / bank / address / 2 spare
;     $CD48 + 8*NN    entry NN's name (up to 8 characters, 0 after)
;     $CE88-$CE8F     the system calls' own variables
;     $CF00 + BB      the bank map: bank BB's owner (00 free, FD a main-RAM
;                     program, FE loaded by hand, FF system, else a bank)
;   At a cold start the monitor sets the map (banks $00-$1F and $C0-$FF
;   reserved, the rest free); L NAME HHHH BB marks a free bank FE.
;
; System calls ($FFB0-$FFC1, JSR from anywhere; not from interrupt
; handlers): BALLOC $FFB0 (A owner, X count, Y 0 programs / 1 documents
; zone: A = first bank, carry set if no room), BFREE $FFB3 (A bank),
; BFREEALL $FFB6 (A owner), BCLAIM $FFB9 (A owner, X bank: carry set if
; someone else has it), VFIND $FFBC (X/Y name: A entry, X/Y its address,
; carry set if none), BOWNER $FFBF (A bank: A owner).
;   Entry NN is called with JSR $CC08+8*NN, or from BASIC with
;   CALL 52232+8*NN. Save the table with S VECTORS CC00.CEFF.
;
; A BRK instruction stops the program and shows where it stopped and the
; registers; the monitor's last address is then set to the BRK.
;
; Interrupts (IRQ, see IRQEN at $D007 in mini6502.bas): the monitor saves A,
; X, Y and BANK on the stack, clears D, selects IRQBANK, reads IRQFLAGS into
; A (which sources fired; reading also releases the IRQ) and JSRs to the
; address in IRQVEC. The handler may use A, X and Y and ends with RTS; the
; monitor then puts the bank and the registers back and returns (RTI).
; To use them: set IRQVEC and IRQBANK, then IRQEN, then CLI.
;
; Entry points kept at the Woz Monitor's addresses, so programs written for
; it keep working:
;   $FF00 RESET    $FF1F GETLINE (monitor prompt)
;   $FFDC PRBYTE   $FFE5 PRHEX   $FFEF ECHO (A preserved)
; and one of its own:
;   $FFD0 FARCALL (see above)
;
; Memory used: $E6-$ED zero page (left free by EhBASIC, so BASIC and the
;              monitor can be used in turn), $0200-$027F input line,
;              $0280-$028D monitor variables.
;=============================================================================

; --- mini6502 I/O --------------------------------------------------------------

; --- memory --------------------------------------------------------------------
        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

SPTR     = $E6           ; 2 bytes: string being printed
XAM     = $E8           ; 2 bytes: last address shown (and R address)
STO     = $EA           ; 2 bytes: next address to store to
VAL     = $EC           ; 2 bytes: hex number just parsed

IN      = $0200         ; input line, ends with CR
MAXLEN  = 126           ; longest line (one byte left for the CR)

LASTC   = $0280         ; last character printed (for NEWLINE)
PMODE    = $0281         ; parser mode, see below
DIGITS  = $0282         ; hex digits in the number being parsed
TMP     = $0283
SAVA    = $0284         ; registers saved by BRK
SAVX    = $0285
SAVY    = $0286
SAVP    = $0287
NEWBANK = $0288         ; bank given to L / S
HAVEBANK = $0289        ; nonzero if one was given
OLDBANK = $028A         ; bank to select again afterwards
VNUM    = $028B         ; V: entry number
VADR    = $028C         ; V: 2 bytes, target address

; far calls
FP      = $E2           ; 2 bytes: points into the far call's inline bytes
FA      = $E4           ; A, X, Y kept while switching
FY      = $E5
FX      = $EE

MODE_XAM   = 0          ; a number shows that address
MODE_BLOCK = 1          ; after '.': a number shows a range
MODE_STORE = 2          ; after ':': numbers are stored

CR      = $0D
BS      = $08
ESC     = $1B
BEL     = $07

.macro  PRINT str               ; prints a zero-terminated string; Y is kept
        lda #<str
        ldx #>str
        jsr puts
.endmacro

;=============================================================================
.segment "CODE"
;=============================================================================

; --- cold start ----------------------------------------------------------------
reset:
        cld
        ldx #$FF
        txs
        lda #CR
        sta LASTC
        PRINT s_banner

; boot: only at a cold start, and only if no keys are waiting
        lda SYSCTL              ; 1 once after power-on / $FF cold reset
        beq monitor
        jsr mapinit             ; a fresh bank map
        lda KBDCR               ; keys already typed in? then leave them to
        bmi monitor             ; the monitor (the key stays waiting)
        lda #<s_bootn
        sta DNAME
        lda #>s_bootn
        sta DNAME+1
        lda #0
        sta DNLEN               ; name ends with $00
        sta DEND                ; no limit
        sta DEND+1
        lda #1                  ; load at the file's own address
        sta DCMD
        lda DSTAT
        beq @booted
        cmp #1                  ; no BOOT file: try the script BOOT.TXT
        bne @prompt             ; (BOOT is there but would not load: prompt)
        lda #<s_boottxt
        sta DNAME
        lda #>s_boottxt
        sta DNAME+1
        lda #6                  ; type it; nothing happens if it is not there
        sta DCMD
@prompt:
        jmp monitor
@booted:
        lda DSTART
        sta XAM
        lda DSTART+1
        sta XAM+1
        PRINT s_boot
        lda XAM+1
        jsr prbyte
        lda XAM
        jsr prbyte
        lda #CR
        jsr putch
        jmp run                 ; JSR to it: an RTS comes back to the prompt

; --- main loop: prompt, read a line, run its commands ---------------------------
monitor:
        cld
        ldx #$FF                ; fresh stack for every line
        txs
        jsr newline
        lda #'>'
        jsr putch
        ldy #0

readkey:
        jsr getkey
        cmp #CR
        beq endline
        cmp #ESC
        beq cancel
        cmp #BS
        beq rubout
        cmp #$7F
        beq rubout
        cmp #' '
        bcc readkey             ; other control keys are ignored
        cmp #'a'
        bcc @store
        cmp #'z'+1
        bcs @store
        and #$DF                ; lower case -> upper case
@store: cpy #MAXLEN
        bcs @full
        sta IN,y
        iny
        jsr putch
        jmp readkey
@full:  lda #BEL                ; line full: beep, ignore the key
        jsr putch
        jmp readkey

rubout:
        cpy #0
        beq readkey
        dey
        lda #BS                 ; the terminal moves left and blanks the cell
        jsr putch
        jmp readkey

cancel:
        lda #'\'
        jsr putch
        jmp monitor

endline:
        sta IN,y                ; CR ends the buffer
        jsr putch

; --- run the commands in the line ----------------------------------------------
        ldy #0
        sty PMODE
parse:
        lda IN,y
        cmp #CR
        beq monitor
        cmp #'.'
        beq @block
        cmp #':'
        beq @store
        cmp #'R'
        beq run
        cmp #'?'
        beq help
        cmp #'S'
        bne @nos
        jmp cmd_save
@nos:   cmp #'L'
        bne @nol
        jmp cmd_load
@nol:   cmp #'$'
        bne @nod
        jmp cmd_dir
@nod:   cmp #'T'
        bne @not
        jmp cmd_type
@not:   cmp #'K'
        bne @nok
        jmp cmd_kill
@nok:   cmp #'W'
        bne @now
        lda #2                  ; clear the screen, cursor home
        sta SYSCTL
        lda #CR                 ; the cursor is at the start of a line
        sta LASTC
        iny
        jmp parse
@now:   cmp #'G'
        bne @nog
        jmp cmd_go
@nog:   cmp #'V'
        bne @nov
        jmp cmd_vec
@nov:   cmp #'X'
        bne @nox
        jmp cmd_exit
@nox:   cmp #'M'
        bne @nom
        jmp cmd_map
@nom:   cmp #'P'                ; (not F: A-F are hex digits)
        bne @nop
        jmp cmd_folder
@nop:   jsr gethex              ; number? (Y moves past its digits)
        bcs number
        iny                     ; anything else separates commands
        jmp parse
@block: lda #MODE_BLOCK
        bne @setmode
@store: lda #MODE_STORE
@setmode:
        sta PMODE
        iny
        jmp parse

help:
        iny
        PRINT s_help
        jmp parse

run:
        jsr @go                 ; the program's RTS returns here
        jmp monitor
@go:    jmp (XAM)

number:
        lda PMODE
        cmp #MODE_STORE
        bne @notst
        lda DIGITS              ; storing: 1-2 digits are a byte, 3-4 digits
        cmp #3                  ; a new address ("D020: 05 D021: 1E" works)
        bcc @store
        lda #MODE_XAM
        sta PMODE
        beq @xam
@notst: cmp #MODE_BLOCK
        beq @block

        ; show one address: it becomes the last address shown and the place
        ; where ':' will store
@xam:   lda VAL
        sta XAM
        sta STO
        lda VAL+1
        sta XAM+1
        sta STO+1
        jsr showaddr
        lda XAM+1               ; an I/O address about to be stored to
        and #$F0                ; ("D203: 41"): do not read it first, as
        cmp #$D0                ; reading can have an effect (a data port
        bne @show               ; moves on, KBD takes the key)
        tya
        pha
        jsr skipsp
        lda IN,y
        tax
        pla
        tay
        cpx #':'
        beq @noshow
@show:  jsr showbyte
@noshow:
        jmp parse

@store: lda VAL
        ldx #0
        sta (STO,x)
        inc STO
        bne @next
        inc STO+1
@next:  jmp parse

@block: lda XAM                 ; show XAM+1 .. VAL
        cmp VAL
        lda XAM+1
        sbc VAL+1
        bcs @done               ; XAM >= VAL: nothing (more) to show
        inc XAM
        bne @noc
        inc XAM+1
@noc:   lda XAM
        and #$07
        bne @byte
        jsr showaddr            ; new line every 8 bytes
@byte:  jsr showbyte
        jmp @block
@done:  lda #MODE_XAM
        sta PMODE
        jmp parse

; Parses hex digits at IN,Y into VAL (only the last 4 digits count).
; Returns carry set if there was at least one digit; Y is moved past them.
gethex:
        lda #0
        sta VAL
        sta VAL+1
        sta DIGITS
@loop:  lda IN,y
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcc @dec
        cmp #'A'
        bcc @end
        cmp #'F'+1
        bcs @end
        sbc #'A'-11             ; carry is clear: A - ('A'-11) - 1 = 10..15
        jmp @digit
@dec:   and #$0F
@digit: sta TMP
        ldx #4
@shift: asl VAL
        rol VAL+1
        dex
        bne @shift
        lda VAL
        ora TMP
        sta VAL
        inc DIGITS
        iny
        jmp @loop
@end:   lda DIGITS
        cmp #1                  ; carry set if DIGITS >= 1
        rts

; --- disk ----------------------------------------------------------------------

; S NAME HHHH.HHHH
cmd_save:
        iny
        jsr getname
        bcc @bad
        jsr skipsp
        jsr gethex
        bcc @bad
        lda VAL
        sta DSTART
        lda VAL+1
        sta DSTART+1
        lda IN,y
        cmp #'.'
        bne @bad
        iny
        jsr gethex
        bcc @bad
        clc                     ; end + 1 ($FFFF + 1 = 0 means "up to $FFFF")
        lda VAL
        adc #1
        sta DEND
        lda VAL+1
        adc #0
        sta DEND+1
        jsr getbank             ; optional bank
        lda #2
        jsr diskbank            ; run the command with that bank selected
        jsr dcheck              ; back to the prompt with a message on error
        jsr newline
        PRINT s_saved
        jmp showrange
@bad:   jmp usage

; L NAME [HHHH]
cmd_load:
        iny
        jsr getname
        bcc @bad
        jsr skipsp
        lda #0
        sta DEND                ; no limit
        sta DEND+1
        jsr gethex
        bcc @own
        lda VAL
        sta DSTART
        lda VAL+1
        sta DSTART+1
        jsr getbank             ; optional bank (only after an address)
        lda #3                  ; load at HHHH
        bne @go
@own:   lda #0
        sta HAVEBANK
        lda #1                  ; load at the file's own address
@go:    jsr diskbank            ; run the command with that bank selected
        jsr dcheck              ; back to the prompt with a message on error
        lda HAVEBANK            ; loaded into a free bank: it is taken now
        beq @nomark
        ldx NEWBANK
        lda BANKMAP,x
        bne @nomark
        lda #OWN_HAND
        sta BANKMAP,x
@nomark:
        lda DSTART              ; R will run what was loaded
        sta XAM
        lda DSTART+1
        sta XAM+1
        jsr newline
        PRINT s_loaded
        jmp showrange
@bad:   jmp usage

; T NAME: the host types the file into the keyboard queue
cmd_type:
        iny
        jsr getname
        bcc @bad
        lda #6
        sta DCMD
        jsr dcheck              ; back to the prompt with a message on error
        jmp monitor             ; the prompt then reads the typed lines
@bad:   jmp usage

; K NAME
cmd_kill:
        iny
        jsr getname
        bcc @bad
        lda #5
        sta DCMD
        jsr dcheck              ; back to the prompt with a message on error
        jsr newline
        PRINT s_deleted
        jmp monitor
@bad:   jmp usage

; P [NAME]: the disk's current folder (its path): shown, or first changed to NAME
; (a folder in it, ".." up, "/" the top, or a path "/GAMES/SAVES")
FPATH   = $0100                 ; (the bottom of the stack page)
cmd_folder:
        iny
        jsr getname
        bcc @show
        lda #9                  ; FOLDER
        sta DCMD
        jsr dcheck              ; back to the prompt with a message on error
@show:  lda #<FPATH             ; WHERE
        sta DSTART
        lda #>FPATH
        sta DSTART+1
        lda #13
        sta DCMD
        jsr newline
        PRINT FPATH
        jmp monitor

; $
cmd_dir:
        lda #4
        sta DCMD
        lda #CR                 ; the host printed the list and ended its line
        sta LASTC
        jsr dcheck              ; back to the prompt with a message on error
        jmp monitor

; G: back to the program that set WARMLO/WARMHI
cmd_go:
        lda WARMLO
        sta XAM
        lda WARMHI
        sta XAM+1
        ora XAM
        bne @go
        jsr newline
        PRINT s_nowarm
        jmp monitor
@go:    jmp run                 ; as R: an RTS comes back to the prompt

; X: quit the emulator (it stops at the end of the current frame)
cmd_exit:
        jsr newline
        PRINT s_bye
        lda #1
        sta SYSCTL
@wait:  jmp @wait

; Reads an optional bank number after a space: HAVEBANK/NEWBANK
getbank:
        lda #0
        sta HAVEBANK
        jsr skipsp
        jsr gethex
        bcc @none
        lda VAL
        sta NEWBANK
        lda #1
        sta HAVEBANK
@none:  rts

; Writes the disk command in A, with NEWBANK selected if HAVEBANK; the bank
; selected before is selected again afterwards, whatever the result
diskbank:
        pha
        lda BANK
        sta OLDBANK
        lda HAVEBANK
        beq @cmd
        lda NEWBANK
        sta BANK
@cmd:   pla
        sta DCMD
        lda OLDBANK
        sta BANK
        rts

; V                 list the vector table
; V NN BB HHHH      set entry NN to call HHHH in bank BB
cmd_vec:
        iny
        jsr skipsp
        jsr gethex
        bcs @set
        jmp vlist
@set:   lda VAL                 ; entry number
        cmp #VTMAX
        bcc *+5
        jmp @bad
        sta VNUM
        jsr skipsp
        jsr gethex
        bcs *+5
        jmp @bad
        lda VAL
        pha                     ; bank
        jsr skipsp
        jsr gethex
        bcs *+5
        jmp @badp
        lda VAL
        sta VADR
        lda VAL+1
        sta VADR+1
        sty TMP                 ; where the name (if any) starts
        jsr vinit               ; make sure the table has its header
        lda VNUM
        jsr ventry              ; VAL = entry address
        ldy #0
        lda #$20                ; JSR $FFD0
        sta (VAL),y
        iny
        lda #<farcall_entry
        sta (VAL),y
        iny
        lda #>farcall_entry
        sta (VAL),y
        iny
        pla                     ; bank
        sta (VAL),y
        iny
        lda VADR
        sta (VAL),y
        iny
        lda VADR+1
        sta (VAL),y
        iny
        lda #0
        sta (VAL),y
        iny
        sta (VAL),y
        lda VNUM                ; the name: up to 8 characters, 0 after
        jsr vnaddr
        ldx TMP
@sk:    lda IN,x
        cmp #' '
        bne @nm
        inx
        bne @sk
@nm:    ldy #0
@nc:    lda IN,x
        cmp #' '+1              ; a space or the CR ends it
        bcc @pad
        sta (VAL),y
        inx
        iny
        cpy #8
        bne @nc
        beq @named
@pad:   lda #0
@pd:    sta (VAL),y
        iny
        cpy #8
        bne @pd
@named: ldx VNUM                ; count = max(count, NN+1)
        inx
        cpx VTCOUNT
        bcc @shown
        stx VTCOUNT
@shown: lda VNUM
        jsr vshow
        jmp monitor
@badp:  pla
@bad:   jsr newline
        PRINT s_vuse
        jmp monitor

; Lists the entries in use
vlist:
        jsr vvalid
        bne @none
        ldx #0
@loop:  cpx VTCOUNT
        bcs @done
        txa
        pha
        jsr vshow
        pla
        tax
        inx
        bne @loop
@done:  jmp monitor
@none:  jsr newline
        PRINT s_vnone
        jmp monitor

; Shows entry A: "NN CCxx: bank BB HHHH" (or "unused")
vshow:
        sta VNUM
        jsr @one
        lda VNUM                ; then its name, if it has one
        jsr vnaddr
        ldy #0
        lda (VAL),y
        beq @nn
        lda #' '
        jsr putch
@ch:    lda (VAL),y
        beq @nn
        jsr putch
        iny
        cpy #8
        bne @ch
@nn:    rts
@one:   pha
        jsr newline
        pla
        pha
        jsr prbyte
        lda #' '
        jsr putch
        pla
        jsr ventry
        lda VAL+1
        jsr prbyte
        lda VAL
        jsr prbyte
        PRINT s_vbank
        ldy #0
        lda (VAL),y
        cmp #$20                ; a far-call stub?
        bne @unused
        ldy #3
        lda (VAL),y
        jsr prbyte
        lda #' '
        jsr putch
        ldy #5
        lda (VAL),y
        jsr prbyte
        dey
        lda (VAL),y
        jmp prbyte
@unused:
        PRINT s_vunused
        rts

; VAL = address of entry A's name (VTNAMES + 8*A)
vnaddr: jsr ventry
        clc
        lda VAL
        adc #<(VTNAMES - VTENTRY)
        sta VAL
        lda VAL+1
        adc #>(VTNAMES - VTENTRY)
        sta VAL+1
        rts

; VAL = address of entry A (VTENTRY + 8*A)
ventry:
        sta VAL
        lda #0
        sta VAL+1
        asl VAL
        rol VAL+1
        asl VAL
        rol VAL+1
        asl VAL
        rol VAL+1
        clc
        lda VAL
        adc #<VTENTRY
        sta VAL
        lda VAL+1
        adc #>VTENTRY
        sta VAL+1
        rts

; Z set if the table has its "VT" signature
vvalid:
        lda VTAB
        cmp #'V'
        bne @no
        lda VTAB+1
        cmp #'T'
@no:    rts

; Writes the header (empty table) unless it is there already
vinit:
        jsr vvalid
        beq @ok
        lda #'V'
        sta VTAB
        lda #'T'
        sta VTAB+1
        lda #0
        sta VTCOUNT
@ok:    rts

; --- the bank map --------------------------------------------------------------

; Cold start: zones $00-$1F and $C0-$FF reserved, programs and documents free
mapinit:
        ldx #0
@l:     lda #OWN_SYSTEM
        cpx #Z_PROGRAMS
        bcc @s
        cpx #Z_SWAP
        bcs @s
        lda #OWN_FREE
@s:     sta BANKMAP,x
        inx
        bne @l
        rts

; M          list the map, one line per run of banks with the same owner
; M BB OO    set bank BB's owner, then list
cmd_map:
        iny
        jsr skipsp
        jsr gethex
        bcc mlist
        lda VAL
        pha
        jsr skipsp
        jsr gethex
        pla
        bcc @bad
        tax
        lda VAL
        sta BANKMAP,x
        jmp mlist
@bad:   jsr newline
        PRINT s_muse
        jmp monitor
mlist:  ldx #0
@run:   stx VADR                ; first bank of the run
        lda BANKMAP,x
        sta VNUM                ; its owner
@more:  cpx #$FF
        beq @end
        lda BANKMAP+1,x
        cmp VNUM
        bne @end
        inx
        bne @more
@end:   stx VADR+1              ; last bank of the run
        jsr newline
        lda VADR
        jsr prbyte
        lda VADR+1
        cmp VADR
        beq @one
        lda #'-'
        jsr putch
        lda VADR+1
        jsr prbyte
        jmp @own
@one:   PRINT s_3sp
@own:   PRINT s_2sp
        lda VNUM
        bne @n0
        PRINT s_ofree
        jmp @next
@n0:    cmp #OWN_SYSTEM
        bne @n1
        PRINT s_osys
        jmp @next
@n1:    cmp #OWN_HAND
        bne @n2
        PRINT s_ohand
        jmp @next
@n2:    cmp #OWN_MAIN
        bne @n3
        PRINT s_omain
        jmp @next
@n3:    PRINT s_obank
        lda VNUM
        jsr prbyte
@next:  ldx VADR+1
        cpx #$FF
        beq @done
        inx
        jmp @run
@done:  jmp monitor

; --- system calls (through the jump table at $FFB0) ------------------------------
SCOWN   = $CE88                 ; their variables, in the system page
SCCNT   = $CE89
SCEND   = $CE8A
SCFIRST = $CE8B
SCN     = $CE8C

; A = owner, X = count, Y = zone (0 programs, 1 documents): A = first bank
balloc: sta SCOWN
        stx SCCNT
        cmp #OWN_FREE           ; (an owner, and at least one bank)
        beq @fail
        cpx #0
        beq @fail
        ldx #Z_PROGRAMS
        lda #Z_PROGRAMS_END + 1
        cpy #0
        beq @z
        ldx #Z_DOCUMENTS
        lda #Z_DOCUMENTS_END + 1
@z:     sta SCEND
@try:   stx SCFIRST             ; a run of SCCNT free banks from here?
        ldy SCCNT
@chk:   cpx SCEND
        bcs @fail
        lda BANKMAP,x
        bne @next
        inx
        dey
        bne @chk
        ldx SCFIRST             ; yes: they are the owner's
        ldy SCCNT
        lda SCOWN
@mk:    sta BANKMAP,x
        inx
        dey
        bne @mk
        lda SCFIRST
        clc
        rts
@next:  inx                     ; a used bank: try after it
        jmp @try
@fail:  sec
        rts

; A = bank: free (not a system bank)
bfree:  tax
        lda BANKMAP,x
        cmp #OWN_SYSTEM
        beq @no
        lda #OWN_FREE
        sta BANKMAP,x
        clc
        rts
@no:    sec
        rts

; A = owner: all its banks free
bfreeall:
        cmp #OWN_FREE
        beq @r
        cmp #OWN_SYSTEM
        beq @r
        sta SCOWN
        ldx #0
@l:     lda BANKMAP,x
        cmp SCOWN
        bne @n
        lda #OWN_FREE
        sta BANKMAP,x
@n:     inx
        bne @l
@r:     clc
        rts

; A = owner, X = bank: the owner's, unless someone else has it (carry set)
bclaim: sta SCOWN
        lda BANKMAP,x
        beq @take
        cmp SCOWN
        beq @take
        sec
        rts
@take:  lda SCOWN
        sta BANKMAP,x
        clc
        rts

; A = bank: A = its owner
bowner: tax
        lda BANKMAP,x
        clc
        rts

; X/Y = a name: A = its far-call entry, X/Y = the entry's address
vfind:  lda SPTR                ; (the monitor's pointer, put back after)
        pha
        lda SPTR+1
        pha
        stx SPTR
        sty SPTR+1
        ldy #0                  ; an empty name finds nothing
        lda (SPTR),y
        cmp #' '+1
        bcs *+5
        jmp @fail
        lda #0
        sta SCN
@ent:   lda SCN                 ; X = the name's offset in its 256-byte half
        asl
        asl
        asl
        tax
        lda #0
        sta SCEND               ; 1 once the name has ended
        tay
@ch:    lda SCEND
        bne @zero
        lda (SPTR),y
        cmp #'a'
        bcc @up
        cmp #'z'+1
        bcs @up
        and #$DF
@up:    cmp #' '+1
        bcs @have
        lda #1
        sta SCEND
@zero:  lda #0
@have:  sta SCCNT
        lda SCN
        cmp #32
        bcs @hi
        lda VTNAMES,x
        jmp @cmp
@hi:    lda VTNAMES+256,x
@cmp:   cmp SCCNT
        bne @miss
        inx
        iny
        cpy #8
        bne @ch
        lda SCN                 ; found: X/Y = VTENTRY + 8 * entry
        sta SCFIRST
        lda #0
        sta SCCNT
        lda SCN
        asl
        rol SCCNT
        asl
        rol SCCNT
        asl
        rol SCCNT
        clc
        adc #<VTENTRY
        sta SCOWN
        lda SCCNT
        adc #>VTENTRY
        sta SCCNT
        pla
        sta SPTR+1
        pla
        sta SPTR
        ldx SCOWN
        ldy SCCNT
        lda SCFIRST
        clc
        rts
@miss:  inc SCN
        lda SCN
        cmp #VTMAX
        bcs *+5
        jmp @ent
@fail:  pla
        sta SPTR+1
        pla
        sta SPTR
        sec
        rts

; --- far call --------------------------------------------------------------------

; JSR farcall / .byte bank / .word address  (entered through $FFD0)
; Switches to the bank, calls the address with A, X, Y as they were, then
; switches back to the caller's bank and returns after the 3 inline bytes'
; owner (a vector table entry returns straight to whoever called the entry).
farcall:
        sta FA
        stx FX
        sty FY
        pla                     ; return address = last byte of the JSR
        sta FP
        pla
        sta FP+1
        lda BANK                ; the caller's bank, for farret
        pha
        lda #>(farret-1)        ; the callee's RTS goes to farret
        pha
        lda #<(farret-1)
        pha
        ldy #3                  ; (the inline bytes are read before the
        lda (FP),y              ; switch: they may be in the banked RAM)
        tax                     ; target high byte
        dey
        lda (FP),y              ; target low byte
        sec                     ; push target-1 for RTS
        sbc #1
        bcs @nb
        dex
@nb:    tay
        txa
        pha
        tya
        pha
        ldy #1
        lda (FP),y              ; the bank to call into
        sta BANK
        lda FA                  ; registers as the caller left them
        ldx FX
        ldy FY
        rts                     ; "return" into the target

; The callee returns here: back to the caller's bank, A X Y and carry kept
farret:
        sta FA
        pla
        sta BANK
        lda FA
        rts

; Returns if the disk command worked; else reports it and goes to the prompt
; (which resets the stack)
dcheck:
        lda DSTAT
        bne diskerr
        rts

; Prints "? disk: <message>" for the status in A
diskerr:
        pha
        jsr newline
        PRINT s_derr
        pla
        sec
        sbc #1
        cmp #7
        bcs @unk
        tax
        lda errlo,x
        pha
        lda errhi,x
        tax
        pla
        jsr puts
@unk:   jmp monitor

usage:
        jsr newline
        PRINT s_what
        jmp monitor

; Prints DSTART.DEND-1 in hex, then back to the prompt
showrange:
        lda DSTART+1
        jsr prbyte
        lda DSTART
        jsr prbyte
        PRINT s_dot
        sec
        lda DEND
        sbc #1
        tax
        lda DEND+1
        sbc #0
        jsr prbyte
        txa
        jsr prbyte
        jmp monitor

; Skips spaces at IN,Y
skipsp:
        lda IN,y
        cmp #' '
        bne @done
        iny
        bne skipsp
@done:  rts

; Reads a file name at IN,Y (up to a space or the end of the line) and puts
; its address and length in DNAME/DNLEN. Carry clear if there was none.
getname:
        jsr skipsp
        sty DNAME               ; IN is page aligned: the low byte is Y
        lda #>IN
        sta DNAME+1
        ldx #0
@loop:  lda IN,y
        cmp #' '
        beq @end
        cmp #CR
        beq @end
        iny
        inx
        bne @loop
@end:   stx DNLEN
        cpx #1                  ; carry set if at least one character
        rts

; --- output --------------------------------------------------------------------

; New line, then "HHHH:" for XAM
showaddr:
        jsr newline
        lda XAM+1
        jsr prbyte
        lda XAM
        jsr prbyte
        lda #':'
        jmp putch

; " BB" for the byte at XAM
showbyte:
        lda #' '
        jsr putch
        ldx #0
        lda (XAM,x)
        jmp prbyte

; Prints A as two hex digits
prbyte:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr prhex
        pla
; Prints the low nibble of A as a hex digit
prhex:
        and #$0F
        ora #'0'
        cmp #'9'+1
        bcc putch
        adc #6                  ; carry is set: +7 gives 'A'..'F'
; Prints A; A, X and Y are kept
putch:
        sta DSP
        sta LASTC
        rts

; Starts a new line unless the cursor is already at the start of one
newline:
        lda LASTC
        cmp #CR
        beq @done
        lda #CR
        jmp putch
@done:  rts

; Prints the zero-terminated string at X (high) A (low); Y is kept
puts:
        sta SPTR
        stx SPTR+1
        tya
        pha
        ldy #0
@loop:  lda (SPTR),y
        beq @done
        jsr putch
        iny
        bne @loop
        inc SPTR+1               ; strings may be longer than 255 bytes
        bne @loop
@done:  pla
        tay
        rts

; Waits for a key and returns it in A (bit 7 cleared)
getkey:
        lda KBDCR
        bpl getkey
        lda KBD
        and #$7F
        rts

; --- BRK -----------------------------------------------------------------------

irq:
        pha
        txa
        pha
        tsx
        lda $0103,x             ; P as pushed
        and #$10                ; B flag: was this a BRK?
        bne @brk
        tya                     ; a real IRQ: A, X, Y and the bank kept
        pha
        lda BANK
        pha
        cld
        lda IRQBANK
        sta BANK
        lda IRQFLAGS            ; the sources (reading releases the IRQ)
        jsr @call
        pla
        sta BANK
        pla
        tay
        pla
        tax
        pla
        rti
@call:  jmp (IRQVEC)
@brk:   pla
        tax
        pla
        sta SAVA

onbrk:
        stx SAVX
        sty SAVY
        pla
        sta SAVP
        pla                     ; return address = BRK + 2
        sec
        sbc #2
        sta XAM
        pla
        sbc #0
        sta XAM+1
        jsr newline
        PRINT s_brk
        lda XAM+1
        jsr prbyte
        lda XAM
        jsr prbyte
        PRINT s_a
        lda SAVA
        jsr prbyte
        PRINT s_x
        lda SAVX
        jsr prbyte
        PRINT s_y
        lda SAVY
        jsr prbyte
        PRINT s_p
        lda SAVP
        jsr prbyte
        PRINT s_s
        tsx
        txa
        jsr prbyte
        lda SAVP                ; interrupts as they were before the BRK
        and #$04
        bne @sei
        cli
@sei:   jmp monitor

nmi:
        jmp monitor

; --- text ----------------------------------------------------------------------
strings:
s_banner:
        .byte CR, "mini6502 monitor 1.0 - ? for help", CR, 0
s_help:
        .byte CR
        .byte "HHHH         show a byte", CR
        .byte "HHHH.HHHH    show a range   (.HHHH continues)", CR
        .byte "HHHH: BB ..  store bytes    (: BB continues)", CR
        .byte "HHHH R       run, RTS returns here", CR
        .byte "S NAME HHHH.HHHH [BB]  save  L NAME [HHHH [BB]]  load (BB: bank)", CR
        .byte "$            list the folder   K NAME  delete a file", CR
        .byte "P [NAME]     the disk's folder (NAME, .. up, / top)", CR
        .byte "T NAME       type a text file as a script", CR
        .byte "W            clear the screen  X  exit mini6502", CR
        .byte "G            go back to the program (BASIC...)", CR
        .byte "V [NN BB HHHH [NAME]]  far-call table at CC00 (FARCALL is FFD0)", CR
        .byte "M [BB OO]    the bank map (set bank BB's owner)", CR
        .byte "Esc cancels the line", CR, 0
s_brk:  .byte "BRK at ", 0
s_a:    .byte "  A=", 0
s_x:    .byte " X=", 0
s_y:    .byte " Y=", 0
s_p:    .byte " P=", 0
s_s:    .byte " S=", 0
s_bye:    .byte "Bye", CR, 0
s_vuse:   .byte "? usage: V   or   V NN BB HHHH [NAME]  (entry 00-27, bank, address)", 0
s_muse:   .byte "? usage: M   or   M BB OO  (bank, owner; 00 = free)", 0
s_3sp:    .byte "   ", 0
s_2sp:    .byte "  ", 0
s_ofree:  .byte "free", 0
s_osys:   .byte "system", 0
s_ohand:  .byte "by hand", 0
s_omain:  .byte "main-RAM program", 0
s_obank:  .byte "bank ", 0
s_vnone:  .byte "no vector table at CC00 (V NN BB HHHH makes one)", 0
s_vbank:  .byte ": bank ", 0
s_vunused: .byte "-- unused", 0
s_nowarm: .byte "? no program to go back to", 0
s_bootn:  .byte "BOOT", 0
s_boottxt: .byte "BOOT.TXT", 0
s_boot:   .byte "Booting BOOT at ", 0
s_saved:  .byte "Saved ", 0
s_deleted: .byte "Deleted", 0
s_loaded: .byte "Loaded ", 0
s_what:   .byte "? usage: S NAME HHHH.HHHH [BB]   L NAME [HHHH [BB]]   K NAME   T NAME   $", 0
s_dot:    .byte ".", 0
s_derr:   .byte "? disk: ", 0
s_e1:     .byte "file not found", 0
s_e2:     .byte "bad file name", 0
s_e3:     .byte "does not fit", 0
s_e4:     .byte "file error", 0
s_e5:     .byte "unknown command", 0
s_e6:     .byte "bad range", 0
s_e7:     .byte "too deep (two levels of folders)", 0
errlo:    .byte <s_e1, <s_e2, <s_e3, <s_e4, <s_e5, <s_e6, <s_e7
errhi:    .byte >s_e1, >s_e2, >s_e3, >s_e4, >s_e5, >s_e6, >s_e7

;=============================================================================
; Woz Monitor compatible entry points
;=============================================================================
.segment "WOZ_RESET"            ; $FF00
        jmp reset
.segment "WOZ_GETLINE"          ; $FF1F
        jmp monitor
.segment "SYSCALLS"             ; $FFB0
        jmp balloc              ; $FFB0
        jmp bfree               ; $FFB3
        jmp bfreeall            ; $FFB6
        jmp bclaim              ; $FFB9
        jmp vfind               ; $FFBC
        jmp bowner              ; $FFBF
.segment "FARCALL"              ; $FFD0
farcall_entry:
        jmp farcall
.segment "WOZ_PRBYTE"           ; $FFDC
        jmp prbyte
.segment "WOZ_PRHEX"            ; $FFE5
        jmp prhex
.segment "WOZ_ECHO"             ; $FFEF
        jmp putch               ; A, X and Y kept

.segment "VECTORS"              ; $FFFA
        .word nmi
        .word reset
        .word irq
