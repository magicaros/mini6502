;=============================================================================
; desk2.asm - mini6502 desktop, bank $15: icons, menus, dialogs
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Called from bank $14 (desk1.asm) through the jump table.
;=============================================================================

        .include "desk.inc"

A32     = $A0                   ; calculator arithmetic, 4 bytes each
B32     = $A4
R32     = $A8
SIGN    = $AC
CNT     = $AD

        .org $E000

        rts                     ; $E000 (the icons are in bank $16 now)
        nop
        nop
        jmp menus               ; $E003
        jmp info                ; $E006 A = file
        jmp rename              ; $E009 A = file; carry clear if renamed
        jmp delete              ; $E00C A = file; carry clear if deleted
        jmp none                ; $E00F (the clock and the calculator
        jmp none                ; $E012  are accessories now: bank $1B,
        jmp none                ; $E015  ACC)
        jmp none                ; $E018
        jmp script              ; $E01B A = 0: LOAD/RUN file X, 1: SYSTEM
        jmp about               ; $E01E
        jmp msg                 ; $E021 A = message
        jmp newdir              ; $E024 carry clear if made
        jmp dup                 ; $E027 A = file; carry clear if copied
        jmp copyto              ; $E02A A = file, Y = 0 copy / 1 move
        jmp classify            ; $E02D FKIND,IDX from the name at DP, D0

none:   rts

; --- the kind of a file (moved from DESK1) -------------------------------------
; FKIND,X from the name at DP and the load address
classify:
        lda #<sysnames          ; the system's own files by name
        sta DQ
        lda #>sysnames
        sta DQ+1
@sys:   ldy #0
        lda (DQ),y
        beq @ext
        jsr samename
        bcc @nexts
        lda #K_SYS
        jmp @set
@nexts: ldy #0                  ; next name in the list
@sk:    lda (DQ),y
        iny
        cmp #0
        bne @sk
        tya
        clc
        adc DQ
        sta DQ
        bcc @sys
        inc DQ+1
        bne @sys
@ext:   ldy #0                  ; the extension: after the last "."
        ldx #$FF
@e:     lda (DP),y
        beq @eend
        cmp #'.'
        bne @en
        tya
        tax
@en:    iny
        bne @e
@eend:  cpx #$FF
        beq @byaddr
        inx                     ; Y = start of the extension
        txa
        tay
        jsr ext3                ; A = its line in exts + 1, 0 none
        beq @byaddr
        tax
        lda extkind-1,x
        jmp @set
@byaddr:
        lda D0                  ; no load address: data
        bne @data
        ldx IDX
        lda FLDH,x
        cmp #$E0                ; $E000: for a bank
        bne @main
        lda FLDL,x
        bne @data
        lda #K_APP
        bne @set
@main:  cmp #$02                ; $0200-$CBFF: the main RAM
        bcc @data
        cmp #$CC
        bcs @data
        lda #K_PROG
        bne @set
@data:  lda #K_DATA
@set:   ldx IDX
        sta FKIND,x
        rts

; Carry set if the name at DP is the one at DQ (upper/lower case alike)
samename:
        ldy #0
@l:     lda (DP),y
        jsr upper
        sta D2
        lda (DQ),y
        cmp D2
        bne @no
        cmp #0
        beq @yes
        iny
        bne @l
@no:    clc
        rts
@yes:   sec
        rts

upper:  cmp #'a'
        bcc @r
        cmp #'z'+1
        bcs @r
        and #$DF
@r:     rts

; Extension at (DP),Y: A = 1 TXT, 2 BAS, 3 DAT, 4 MUS, 5 PIC, 0 other (Z)
ext3:   sty D2
        ldx #0
@x:     ldy D2
        lda (DP),y
        jsr upper
        cmp exts,x
        bne @nx
        iny
        lda (DP),y
        jsr upper
        cmp exts+1,x
        bne @nx
        iny
        lda (DP),y
        jsr upper
        cmp exts+2,x
        bne @nx
        iny
        lda (DP),y
        bne @nx
        txa                     ; x = 0, 3, 6.. -> 1, 2, 3..
        ldx #0
@c:     inx
        sec
        sbc #3
        bcs @c
        txa
        rts
@nx:    inx
        inx
        inx
        cpx #NEXT * 3
        bne @x
        lda #0
        rts
; the extensions the desktop knows, and their kinds (an extension more:
; here, its kind in desk.inc, an icon in icons.py, a name in kinds and in
; DESK1's kindnames; a program that opens it: DESK1's withtab and opener)
exts:   .byte "TXTBASDATMUSPICPIXASMSPR"
NEXT    = 8
extkind: .byte K_TEXT, K_BASIC, K_DATA, K_MUSIC, K_PICT, K_PIX, K_ASM, K_DATA
sysnames:
        .byte "TK1", 0, "TK2", 0, "TK3", 0, "TK4", 0, "TK5", 0, "ACC", 0, "NOTE2", 0, "TRACKER2", 0, "PAINT2", 0, "PIXEL2", 0, "DESK1", 0, "DESK2", 0, "DESK3", 0, "VECTORS", 0, 0


; --- the menu bar -----------------------------------------------------------------------
menus:  LDW r0, menudef
        TK TK_MENUBAR
        rts
menudef:
        .byte "mini6502", 0, "About the desktop...", 0, 0  ; (+ accessories)
        .byte "File", 0, "Open/O", 0, "Get info/G", 0, "Rename...", 0
        .byte "Delete.../D", 0, "-", 0, "New folder...", 0, "Duplicate.../U", 0
        .byte "Copy to...", 0, "Move to...", 0, "-", 0, "Back to BASIC/Q", 0, 0
        .byte "View", 0, "by Icon", 0, "by Name", 0, "-", 0, "Refresh/R", 0, 0
        .byte "Special", 0, "Monitor", 0, "Shutdown", 0, 0
        .byte 0

; --- building strings in SCRATCH -----------------------------------------------------
sbegin: lda #0
        sta SLEN
        rts
sput:   ldx SLEN
        sta SCRATCH,x
        inc SLEN
        lda #0
        sta SCRATCH+1,x
        rts
; the string at XA (this bank or fixed RAM)
sstr:   sta DQ
        stx DQ+1
        ldy #0
@l:     lda (DQ),y
        beq @e
        sty CNT
        jsr sput
        ldy CNT
        iny
        bne @l
@e:     rts
; file A's name
sname:  tax
        lda FNL,x
        pha
        lda FNH,x
        tax
        pla
        jmp sstr
; NUM as decimal (no leading zeros)
sdec:   ldy #0
        sty D2
@d:     ldx #0
@s:     lda NUM
        sec
        sbc p10l,y
        sta D1
        lda NUM+1
        sbc p10h,y
        bcc @o
        sta NUM+1
        lda D1
        sta NUM
        inx
        bne @s
@o:     txa
        bne @dig
        cpy #4
        beq @dig
        lda D2
        beq @nx
@dig:   inc D2
        txa
        ora #'0'
        sty CNT
        jsr sput
        ldy CNT
@nx:    iny
        cpy #5
        bne @d
        rts
p10l:   .byte <10000, <1000, <100, <10, <1
p10h:   .byte >10000, >1000, >100, >10, >1
; A as 2 hex digits
shex:   pha
        lsr
        lsr
        lsr
        lsr
        jsr @n
        pla
        and #$0F
@n:     cmp #10
        bcc @d
        adc #6
@d:     adc #'0'
        jmp sput

; --- Get info ------------------------------------------------------------------------------
info:   sta IDX
        jsr sbegin
        lda IDX
        jsr sname
        lda #13
        jsr sput
        lda #<s_kind
        ldx #>s_kind
        jsr sstr
        ldx IDX
        lda FKIND,x
        asl
        tax
        ldy kinds,x
        lda kinds+1,x
        tax
        tya
        jsr sstr
        ldx IDX                 ; a folder: nothing more
        lda FKIND,x
        cmp #K_FOLDER
        beq @show
        lda #13
        jsr sput
        lda #<s_size
        ldx #>s_size
        jsr sstr
        ldx IDX
        lda FSZL,x
        sta NUM
        lda FSZH,x
        sta NUM+1
        jsr sdec
        lda #<s_bytes
        ldx #>s_bytes
        jsr sstr
        lda #13
        jsr sput
        lda #<s_load
        ldx #>s_load
        jsr sstr
        ldx IDX
        lda FLDH,x
        jsr shex
        ldx IDX
        lda FLDL,x
        jsr shex
@show:  LDW r0, SCRATCH
        LDW r1, 0
        TK TK_ALERT
        rts
kinds:  .word k0, k1, k2, k3, k4, k5, k0, k7, k8, k9, k10, k11
k7:     .byte "folder", 0
k8:     .byte "song (opens in TRACKER)", 0
k9:     .byte "picture (opens in PAINT)", 0
k10:    .byte "pixel picture (opens in PIXEL)", 0
k11:    .byte "6502 source (opens in ASM, or NOTE)", 0
k0:     .byte "data", 0
k1:     .byte "text (opens in NOTE)", 0
k2:     .byte "BASIC program", 0
k3:     .byte "program in the main RAM", 0
k4:     .byte "program for a bank", 0
k5:     .byte "part of the system", 0
s_kind: .byte "Kind: ", 0
s_size: .byte "Size: ", 0
s_bytes: .byte " bytes", 0
s_load: .byte "Load address: $", 0

; --- Rename ---------------------------------------------------------------------------------
rename: sta IDX
        tax                     ; the old name as the answer to edit
        lda FNL,x
        sta DP
        lda FNH,x
        sta DP+1
        ldy #0
@c:     lda (DP),y
        sta NAMEBUF,y
        beq @a
        iny
        cpy #40
        bne @c
        lda #0
        sta NAMEBUF,y
@a:     LDW r0, s_newname
        LDW r1, NAMEBUF
        LDW r2, 40
        TK TK_ASK
        bcs @r
        ldx IDX
        lda FNL,x
        sta DNAME
        lda FNH,x
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, NAMEBUF
        lda #8                  ; RENAME
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_norename
        LDW r1, 0
        TK TK_ALERT
        sec
        rts
@ok:    clc
@r:     rts
s_newname: .byte "New name:", 0
s_norename: .byte "Could not rename it: that name is taken", 13
            .byte "or not valid (A-Z a-z 0-9 . _ -).", 0

; --- Delete ----------------------------------------------------------------------------------
delete: sta IDX
        tax
        lda FKIND,x
        cmp #K_FOLDER
        bne @file
        jmp deldir
@file:  jsr sbegin
        lda #<s_del1
        ldx #>s_del1
        jsr sstr
        lda IDX
        jsr sname
        lda #<s_del2
        ldx #>s_del2
        jsr sstr
        LDW r0, SCRATCH
        LDW r1, s_delbtn
        TK TK_ALERT
        cmp #0
        bne @no
        ldx IDX
        lda FNL,x
        sta DNAME
        lda FNH,x
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #5                  ; DELETE
        sta DCMD
        clc
        rts
@no:    sec
        rts
s_del1: .byte "Delete ", 0
s_del2: .byte "?", 13, "It cannot be brought back.", 0
s_delbtn: .byte "Delete|Cancel", 0

; The folder IDX deleted (only when it is empty)
deldir: jsr sbegin
        lda #<s_deld1
        ldx #>s_deld1
        jsr sstr
        lda IDX
        jsr sname
        lda #<s_deld2
        ldx #>s_deld2
        jsr sstr
        LDW r0, SCRATCH
        LDW r1, s_delbtn
        TK TK_ALERT
        cmp #0
        bne @no
        jsr idxname
        lda #11                 ; DELETE FOLDER
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_notempty
        jmp alert
@ok:    clc
        rts
@no:    sec
        rts
s_deld1: .byte "Delete the folder ", 0
s_deld2: .byte "?", 0
s_notempty: .byte "That folder is not empty: only an empty", 13
            .byte "folder can be deleted.", 0

; DNAME = file IDX's name
idxname:
        ldx IDX
        lda FNL,x
        sta DNAME
        lda FNH,x
        sta DNAME+1
        lda #0
        sta DNLEN
        rts

; An alert with r0 and OK; carry set
alert:  LDW r1, 0
        TK TK_ALERT
        sec
        rts

; The answer to an ASK (NAMEBUF) not accepted by the disk: why (DSTAT)
diskerr:
        LDW r0, s_taken
        lda DSTAT
        cmp #4
        beq alert
        LDW r0, s_deep
        lda DSTAT
        cmp #7
        beq alert
        LDW r0, s_badname
        jmp alert
s_taken:   .byte "That name is taken already.", 0
s_deep:    .byte "Folders go two levels deep, no more.", 0
s_badname: .byte "That name cannot be used: A-Z a-z 0-9 . _ -", 13
           .byte "(up to 64), no spaces.", 0

; --- New folder -----------------------------------------------------------------------------
newdir: ldx #0
@c:     lda s_newdir,x
        sta NAMEBUF,x
        beq @a
        inx
        bne @c
@a:     LDW r0, s_newdirp
        LDW r1, NAMEBUF
        LDW r2, 40
        TK TK_ASK
        bcs @r
        LDW DNAME, NAMEBUF
        lda #0
        sta DNLEN
        lda #10                 ; NEW FOLDER
        sta DCMD
        lda DSTAT
        beq @ok
        jmp diskerr
@ok:    clc
@r:     rts
s_newdir:  .byte "FOLDER", 0
s_newdirp: .byte "Name of the new folder:", 0

; --- Duplicate: a copy in the same folder, named NAME-COPY.EXT (or as typed) -----
dup:    sta IDX
        tax
        lda FNL,x
        sta DP
        lda FNH,x
        sta DP+1
        ldy #0                  ; the extension: after the last "."
        ldx #$FF
@e:     lda (DP),y
        beq @ee
        cmp #'.'
        bne @en
        tya
        tax
@en:    iny
        bne @e
@ee:    stx D3                  ; ($FF: none)
        ldy #0
        ldx #0
@n:     cpy D3                  ; the name up to the extension
        beq @cp
        lda (DP),y
        beq @cp
        sta NAMEBUF,x
        inx
        iny
        bne @n
@cp:    sty D2
        ldy #0
@k:     lda s_copy,y            ; then "-COPY"
        beq @x
        sta NAMEBUF,x
        inx
        iny
        bne @k
@x:     ldy D2                  ; then the extension
@xl:    lda (DP),y
        sta NAMEBUF,x
        beq @a
        inx
        iny
        cpx #40
        bcc @xl
        lda #0
        sta NAMEBUF,x
@a:     LDW r0, s_dupp
        LDW r1, NAMEBUF
        LDW r2, 40
        TK TK_ASK
        bcs @r
        jsr idxname
        LDW DSTART, NAMEBUF
        lda #12                 ; COPY
        sta DCMD
        lda DSTAT
        beq @ok
        jmp diskerr
@ok:    clc
@r:     rts
s_copy: .byte "-COPY", 0
s_dupp: .byte "Name of the copy:", 0

; --- Copy to... / Move to...: the file dialog picks the folder (and name) -----
copyto: sta IDX
        sty D3                  ; 0 copy, 1 move
        LDW DSTART, SRCP        ; here: "/PATH" -> SRCP, then "/NAME"
        lda #13
        sta DCMD
        ldx IDX
        lda FNL,x
        sta DP
        lda FNH,x
        sta DP+1
        LDW DQ, SRCP
        jsr addname             ; SRCP = /PATH/NAME
        ldy #0                  ; the dialog starts with the same name
@c:     lda (DP),y
        sta NAMEBUF,y
        beq @d
        iny
        cpy #40
        bne @c
        lda #0
        sta NAMEBUF,y
@d:     LDW r0, s_copyp
        lda D3
        beq @p
        LDW r0, s_movep
@p:     LDW r1, NAMEBUF
        LDW r2, 0
        ldy #1                  ; (as Save: any name, any folder)
        TK TK_FILEDIALOG
        bcs @r
        LDW DSTART, DSTP        ; where it goes: /THERE/NAME
        lda #13
        sta DCMD
        LDW DP, NAMEBUF
        LDW DQ, DSTP
        jsr addname
        jsr back                ; (the desktop stays in its folder)
        LDW DNAME, SRCP
        lda #0
        sta DNLEN
        LDW DSTART, DSTP
        lda #12                 ; COPY
        ldx D3
        beq @go
        lda #8                  ; RENAME: moved
@go:    sta DCMD
        lda DSTAT
        beq @ok
        jmp diskerr
@ok:    clc
@r:     rts
s_copyp: .byte "Copy it to which folder, as:", 0
s_movep: .byte "Move it to which folder, as:", 0

; The desktop's folder again: SRCP up to its last "/" ("/" for the top)
back:   ldy #0
        ldx #0
@l:     lda SRCP,y              ; X = where the last "/" is
        beq @e
        cmp #'/'
        bne @n
        tya
        tax
@n:     iny
        bne @l
@e:     cpx #0
        bne @cp0
        inx                     ; the top: "/"
@cp0:   ldy #0
@cp:    lda SRCP,y
        sta SCRATCH,y
        iny
        dex
        bne @cp
        lda #0
        sta SCRATCH,y
        LDW DNAME, SCRATCH
        lda #0
        sta DNLEN
        lda #9                  ; FOLDER
        sta DCMD
        rts

; The path at DQ + "/" + the name at DP (no "/" twice at the top)
addname:
        ldy #0
@e:     lda (DQ),y              ; the end of the path
        beq @end
        iny
        bne @e
@end:   dey                     ; "/" at the end already (the top)?
        lda (DQ),y
        iny
        cmp #'/'
        beq @nm
        lda #'/'
        sta (DQ),y
        iny
@nm:    tya
        clc
        adc DQ
        sta DQ
        bcc @n
        inc DQ+1
@n:     ldy #0
@c:     lda (DP),y
        sta (DQ),y
        beq @r
        iny
        cpy #64
        bne @c
        lda #0
        sta (DQ),y
@r:     rts

; --- scripts typed into BASIC after the desktop quits ----------------------------------
script: pha
        stx IDX
        jsr sbegin
        pla
        bne @sys
        lda #<s_loadq
        ldx #>s_loadq
        jsr sstr
        lda IDX
        jsr sname
        lda #<s_run
        ldx #>s_run
        jsr sstr
        jmp @save
@sys:   lda #<s_system
        ldx #>s_system
        jsr sstr
@save:  LDW DSTART, SCRATCH     ; SAVE it, TYPE it, DELETE it
        lda #<SCRATCH
        clc
        adc SLEN
        sta DEND
        lda #>SCRATCH
        adc #0
        sta DEND+1
        LDW DNAME, s_runfile
        lda #0
        sta DNLEN
        lda #2
        sta DCMD
        lda #6
        sta DCMD
        lda #5
        sta DCMD
        rts
s_loadq: .byte "LOAD ", 34, 0
s_run:   .byte 34, 13, "RUN", 13, 0
s_system: .byte "SYSTEM", 13, 0
s_runfile: .byte "DESK.RUN", 0

; --- About and messages ---------------------------------------------------------------
about:  LDW r0, s_about
        LDW r1, 0
        TK TK_ALERT
        rts
s_about: .byte "mini6502 desktop", 13, 13
         .byte "Double-click a file to open it: programs run,", 13
         .byte "text opens in NOTE, BASIC programs in BASIC.", 13
         .byte "Folders: double-click to go in, .. to go up.", 13
         .byte "After a program, F1 then G comes back here.", 13, 13
         .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
         .byte "With the help of Claude AI.", 0

msg:    LDW r0, s_noedit
        LDW r1, 0
        TK TK_ALERT
        rts
s_noedit: .byte "EDIT is not on the disk: text files", 13
          .byte "open with it.", 0

; --- variables ---------------------------------------------------------------------------
SLEN:   .res 1

