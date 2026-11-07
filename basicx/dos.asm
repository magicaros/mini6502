; dos.asm - DOS, the mini6502 BASIC extension for the disk's folders and
; files (bank $01). See README.txt.
; Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
; personal, non-commercial use only (see basic/README.txt).
; mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.
;
;   L DOS E000 01     then start BASIC (A000R), or G / A003R back into it
; Commands (names are any string expressions):
;   !CD                     print the current folder ("/", "/GAMES"...)
;   !CD "name"              the current folder becomes name: a folder in
;                           it, ".." (up), "/" (the top) or a path
;                           "/GAMES/SAVES"
;   !MD "name"              a new folder (two levels deep at most)
;   !RD "name"              delete a folder (only an empty one)
;   !COPY "from","to"       copy a file ("to" may be a path: "/GAMES/X")
;   !MOVE "from","to"       rename a file, or move it ("/GAMES/X")
;   !HELP                   every extension's commands (as GFX's)
; LOAD, SAVE, KILL, DIR and GFX's !BLOAD / !BSAVE work in the current
; folder (or with a path from the top: LOAD "/GAMES/X").

        .include "mini6502.inc"
        .include "bx.inc"

        .org $E000
        .byte "BX", 2
        jmp statement           ; $E003
        jmp init                ; $E006
        jmp function            ; $E009
        .byte "DOS", 0, 0, 0, 0, 0      ; $E00C its name (8)
        .word keywords          ; $E014 its commands (for !HELP)
        .word 0                 ; $E016 its functions: none

init:   rts

function:
        sec                     ; (no functions)
        rts

statement:
        ldx #<keywords
        ldy #>keywords
        jsr XMATCH
        bcs @no                 ; not ours
        asl
        tax
        lda cmds+1,x
        pha
        lda cmds,x
        pha
@no:    rts

done:   clc
        rts

        .include "bxmatch.inc"

cmds:   .word c_cd-1, c_md-1, c_rd-1, c_copy-1, c_move-1, c_help-1
keywords:
        .byte "C", 'D'+$80, "M", 'D'+$80, "R", 'D'+$80
        .byte "COP", 'Y'+$80, "MOV", 'E'+$80, "HEL", 'P'+$80
        .byte 0

; !HELP (when GFX is not loaded: it answers first otherwise)
c_help: jmp bxhelp

        .include "bxhelp.inc"

; a string -> NBUF (with a 0 after it), DNAME = NBUF
name:   jsr XGETSTR
        stx $F8
        sty $F9
        tay                     ; (64 characters at most)
        cpy #65
        bcc @c
        ldy #64
@c:     lda #0
        sta NBUF,y
@l:     dey
        bmi @e
        lda ($F8),y
        sta NBUF,y
        jmp @l
@e:     lda #<NBUF
        sta DNAME
        lda #>NBUF
        sta DNAME+1
        lda #0
        sta DNLEN
        rts

; disk command A, this bank selected meanwhile (BASIC's disk error message
; if it failed: "File" for a name taken, a folder not empty, too deep)
disk:   ldx BANK
        jmp XDISK

; !CD ["name"]
c_cd:   jsr XCHRGOT             ; nothing after it: print the folder
        beq @show
        jsr name
        lda #9                  ; FOLDER
        jsr disk
        jmp done
@show:  lda #<PBUF              ; WHERE
        sta DSTART
        lda #>PBUF
        sta DSTART+1
        lda #13
        jsr disk
        ldy #0
@p:     lda PBUF,y
        beq @e
        sty $F8
        jsr XPRINT
        ldy $F8
        iny
        bne @p
@e:     jsr XCRLF
        jmp done

; !MD "name"
c_md:   jsr name
        lda #10                 ; NEW FOLDER
        jsr disk
        jmp done

; !RD "name"
c_rd:   jsr name
        lda #11                 ; DELETE FOLDER
        jsr disk
        jmp done

; !COPY "from","to" and !MOVE "from","to"
c_copy: lda #12                 ; COPY
        bne two
c_move: lda #8                  ; RENAME
two:    sta CMD
        jsr name                ; from -> NBUF, then -> FBUF
        ldy #64
@f:     lda NBUF,y
        sta FBUF,y
        dey
        bpl @f
        jsr XCOMMA
        jsr name                ; to -> NBUF: START
        lda #<NBUF
        sta DSTART
        lda #>NBUF
        sta DSTART+1
        lda #<FBUF
        sta DNAME
        lda #>FBUF
        sta DNAME+1
        lda CMD
        jsr disk
        jmp done

CMD:    .byte 0
NBUF:   .res 66
FBUF:   .res 66
PBUF:   .res 140
