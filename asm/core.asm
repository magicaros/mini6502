; Native NMOS 6502 two-pass assembler. Executed in ASM's private RAM image.
; ABI: $8400 assemble gap-buffer GS=$10/GE=$12, $8403 save binary INBUF=$350.
; No host-side assembler is used at runtime.
        .include "mini6502.inc"
        .macpack longbranch
SRC = $40
IDX = $42
PASS = $43
PC = $44
OUT = $46
VAL = $48
TMP = $4A
SPTR = $4C
NSYM = $4E
LINE = $50
OP = $52
AMODE = $53
REF = $54
UNDEF = $55
FORCE = $56
SIGN = $57
PART = $58
BASE = $59
NCHAR = $5A
TOKLEN = $5B
SAVEDSP = $5C
ORIGINSET = $5D
EMITBYTE = $5E
SAVIDX = $5F
TOKEN = $C700
LINEBUF = $C600
SYMS = $B000
RESULT = $C400
ERRLINE = $C401
ORIGIN = $C403
LENGTH = $C405
IMAGEBANK = $C407
MESSAGE = $C500
OLD_BANK = $C408
EOFFLAG = $C409
FILL = $C40A
COUNT = $C40B
SYMKIND = $C40D
LABEL = $C720
        .org $8400
        jmp assemble
        jmp save_binary

assemble:
        cld
        tsx
        stx SAVEDSP
        lda #0
        sta RESULT
        sta NSYM
        sta NSYM+1
        sta PASS
@pass: lda #0
        sta PC
        sta PC+1
        sta ORIGINSET
        sta EOFFLAG
        sta SRC
        sta LINE+1
        lda #4
        sta SRC+1
        lda #1
        sta LINE
        lda #<$4400
        sta OUT
        lda #>$4400
        sta OUT+1
@line: jsr read_line
        bcs @endpass
        lda #0
        sta IDX
        jsr statement
        jsr trailing
        inc LINE
        bne @line
        inc LINE+1
        jmp @line
@endpass:
        lda PASS
        bne @done
        inc PASS
        jmp @pass
@done: sec
        lda OUT
        sbc #<$4400
        sta LENGTH
        lda OUT+1
        sbc #>$4400
        sta LENGTH+1
        ora LENGTH
        jeq err_empty
        ; Success, also used if the binary save prompt is cancelled.
        lda #<msg_ok
        ldx #>msg_ok
        jmp message

; read one CR/LF-terminated source line, traversing the editor's gap.
read_line:
        lda EOFFLAG
        bne @eof
        ldx #0
@next: lda SRC
        cmp $10
        bne @read
        lda SRC+1
        cmp $11
        bne @read
        lda $12
        sta SRC
        lda $13
        sta SRC+1
@read: lda SRC+1
        cmp #$44
        bcs @last
        ldy #0
        lda (SRC),y
        inc SRC
        bne :+
        inc SRC+1
:      cmp #13
        beq @done
        cmp #10
        beq @done
        cpx #254
        jcs err_longline
        sta LINEBUF,x
        inx
        jmp @next
@last: inc EOFFLAG
        cpx #0
        beq @eof
@done: lda #0
        sta LINEBUF,x
        clc
        rts
@eof:  sec
        rts

peek:   ldy IDX
        lda LINEBUF,y
        rts
skip:   jsr peek
        cmp #' '
        beq @advance
        cmp #9
        bne @done
@advance:
        inc IDX
        jmp skip
@done: ora #0                  ; callers test the returned character for NUL
        rts
upper:  cmp #'a'
        bcc :+
        cmp #'z'+1
        bcs :+
        and #$DF
:       rts
; C=0 for letters or underscore, C=1 otherwise.
letter: jsr upper
        cmp #'_'
        beq @yes
        cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcc @yes
@no:   sec
        rts
@yes:  clc
        rts

token:  ldx #0
        jsr peek
        cmp #'.'
        bne @char
        sta TOKEN,x
        inx
        inc IDX
@next: jsr peek
@char: jsr letter
        bcc @store
        cpx #0
        beq @end
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcs @end
@store: cpx #15
        jcs err_symbol_long
        sta TOKEN,x
        inx
        inc IDX
        jmp @next
@end:  stx TOKLEN
        lda #0
        sta TOKEN,x
        cpx #0
        jeq err_syntax
        rts

statement:
        jsr skip
        beq @done
        cmp #';'
        beq @done
        cmp #'*'
        beq @star
        jsr token
        jsr skip
        cmp #':'
        beq @label
        cmp #'='
        beq @equ
        jmp operation
@star: inc IDX
        jsr skip
        cmp #'='
        jne err_syntax
        inc IDX
        jmp org
@label:
        inc IDX
        lda PC
        sta VAL
        lda PC+1
        sta VAL+1
        lda #0
        sta SYMKIND
        jsr define
        jsr skip
        beq @done
        cmp #';'
        beq @done
        jsr token
        jmp operation
@equ:  ldx #15
@copy: lda TOKEN,x
        sta LABEL,x
        dex
        bpl @copy
        inc IDX
        jsr expression
        lda UNDEF
        jne err_forward
        ldx #15
@back: lda LABEL,x
        sta TOKEN,x
        dex
        bpl @back
        lda #1
        sta SYMKIND
        jmp define
@done: rts

trailing:
        jsr skip
        beq @ok
        cmp #';'
        jne err_syntax
@ok:   rts

; Symbol entries: 16-byte zero-padded name, value (2), kind, spare.
find_symbol:
        lda #<SYMS
        sta SPTR
        lda #>SYMS
        sta SPTR+1
        lda NSYM
        sta TMP
        lda NSYM+1
        sta TMP+1
@entry: lda TMP
        ora TMP+1
        beq @missing
        ldy #0
@name: lda TOKEN,y
        cmp (SPTR),y
        bne @next
        cmp #0
        beq @found
        iny
        bne @name
@next: clc
        lda SPTR
        adc #20
        sta SPTR
        bcc :+
        inc SPTR+1
:      lda TMP
        bne :+
        dec TMP+1
:      dec TMP
        jmp @entry
@found:clc
        rts
@missing:
        sec
        rts

define: jsr find_symbol
        lda PASS
        bne @check
        jcc err_duplicate
        lda NSYM+1
        jne err_symbols_full
        ldy #0
@copy: lda TOKEN,y
        sta (SPTR),y
        beq @pad
        iny
        bne @copy
@pad:  lda #0
@zero: sta (SPTR),y
        iny
        cpy #16
        bcc @zero
        lda VAL
        sta (SPTR),y
        iny
        lda VAL+1
        sta (SPTR),y
        iny
        lda SYMKIND
        sta (SPTR),y
        inc NSYM
        bne @done
        inc NSYM+1
@done: rts
@check: jcs err_phase
        ldy #16
        lda VAL
        cmp (SPTR),y
        jne err_phase
        iny
        lda VAL+1
        cmp (SPTR),y
        jne err_phase
        rts

; Expressions: unary + - < >, hex $, binary %, decimal, 'c', *, symbols;
; left-associative + and -, with 16-bit arithmetic. No implicit relaxation:
; symbolic memory operands use absolute modes unless prefixed with <.
expression:
        lda #0
        sta REF
        sta UNDEF
        sta FORCE
        jsr atom
@next: jsr skip
        cmp #'+'
        beq @plus
        cmp #'-'
        bne @done
        lda #1
        bne @save
@plus: lda #0
@save: pha
        lda VAL+1
        pha
        lda VAL
        pha
        inc IDX
        jsr atom
        pla
        sta TMP
        pla
        sta TMP+1
        pla
        bne @sub
        clc
        lda TMP
        adc VAL
        sta VAL
        lda TMP+1
        adc VAL+1
        sta VAL+1
        jmp @next
@sub:  sec
        lda TMP
        sbc VAL
        sta VAL
        lda TMP+1
        sbc VAL+1
        sta VAL+1
        jmp @next
@done: rts

atom:   lda #0
        sta SIGN
        sta PART
        jsr skip
        cmp #'<'
        beq @low
        cmp #'>'
        beq @high
        jmp @sign
@low:  lda #1
        sta FORCE
        bne @part
@high: lda #2
@part: sta PART
        inc IDX
        jsr skip
@sign: cmp #'+'
        beq @signed
        cmp #'-'
        bne @value
        inc SIGN
@signed:
        inc IDX
        jsr skip
@value: cmp #'$'
        beq @hex
        cmp #'%'
        beq @binary
        cmp #39
        beq @char
        cmp #'*'
        beq @pc
        cmp #'0'
        bcc @symbol
        cmp #'9'+1
        bcs @symbol
        lda #10
        bne @number
@hex:  inc IDX
        lda #16
        bne @number
@binary:inc IDX
        lda #2
@number:
        sta BASE
        jsr number
        jmp @finish
@pc:   inc IDX
        lda PC
        sta VAL
        lda PC+1
        sta VAL+1
        jmp @finish
@char: inc IDX
        jsr peek
        jeq err_syntax
        sta VAL
        lda #0
        sta VAL+1
        inc IDX
        jsr peek
        cmp #39
        jne err_syntax
        inc IDX
        jmp @finish
@symbol:
        jsr token
        inc REF
        jsr find_symbol
        bcs @unknown
        ldy #16
        lda (SPTR),y
        sta VAL
        iny
        lda (SPTR),y
        sta VAL+1
        jmp @finish
@unknown:
        lda PASS
        jne err_undefined
        inc UNDEF
        lda #0
        sta VAL
        sta VAL+1
@finish:
        lda SIGN
        beq @partdone
        sec
        lda #0
        sbc VAL
        sta VAL
        lda #0
        sbc VAL+1
        sta VAL+1
@partdone:
        lda PART
        beq @done
        cmp #2
        bne :+
        lda VAL+1
        sta VAL
:      lda #0
        sta VAL+1
@done: rts

number: lda #0
        sta VAL
        sta VAL+1
        sta NCHAR
@digit: jsr peek
        jsr upper
        cmp #'0'
        bcc @done
        cmp #'9'+1
        bcc @decimal
        cmp #'A'
        bcc @done
        cmp #'F'+1
        bcs @done
        sec
        sbc #'A'-10
        bne @test
@decimal:
        sec
        sbc #'0'
@test: cmp BASE
        bcs @done
        pha
        ; VAL *= BASE by bounded repeated addition (at most 16 iterations).
        lda VAL
        sta TMP
        lda VAL+1
        sta TMP+1
        lda #0
        sta VAL
        sta VAL+1
        ldx BASE
@mul:  clc
        lda VAL
        adc TMP
        sta VAL
        lda VAL+1
        adc TMP+1
        sta VAL+1
        jcs err_range
        dex
        bne @mul
        pla
        clc
        adc VAL
        sta VAL
        bcc :+
        inc VAL+1
        jeq err_range
:      inc NCHAR
        inc IDX
        jmp @digit
@done: lda NCHAR
        jeq err_syntax
        rts

operation:
        ; directives, exact names including their leading dot
        ldx #0
@dir:  lda dirs_lo,x
        sta SPTR
        lda dirs_hi,x
        sta SPTR+1
        ldy #0
@cmp:  lda TOKEN,y
        cmp (SPTR),y
        bne @nextdir
        cmp #0
        beq @directive
        iny
        bne @cmp
@nextdir:
        inx
        cpx #6
        bcc @dir
        jmp instruction
@directive:
        txa
        asl
        tax
        lda dirs_jump+1,x
        pha
        lda dirs_jump,x
        pha
        rts
org:    jsr expression
        lda UNDEF
        jne err_forward
        lda ORIGINSET
        bne @gap
        lda VAL
        sta ORIGIN
        sta PC
        lda VAL+1
        sta ORIGIN+1
        sta PC+1
        inc ORIGINSET
        rts
@gap:  lda VAL
        cmp PC
        lda VAL+1
        sbc PC+1
        jcc err_origin
        lda VAL
        sta COUNT
        lda VAL+1
        sta COUNT+1
@fill: lda PC
        cmp COUNT
        bne @emit
        lda PC+1
        cmp COUNT+1
        beq @done
@emit: lda #0
        jsr emit
        jmp @fill
@done: rts

data_bytes:
        jsr skip
        cmp #'"'
        beq @string
        jsr expression
        jsr byte_value
        jsr emit
        jmp @separator
@string:
        inc IDX
@char: jsr peek
        jeq err_syntax
        inc IDX
        cmp #'"'
        beq @separator
        jsr emit
        jmp @char
@separator:
        jsr skip
        cmp #','
        bne @done
        inc IDX
        jmp data_bytes
@done: rts

data_words:
        jsr expression
        lda VAL+1
        pha
        lda VAL
        jsr emit
        pla
        jsr emit
        jsr skip
        cmp #','
        bne @done
        inc IDX
        jmp data_words
@done: rts

reserve:
        jsr expression
        lda UNDEF
        jne err_forward
        lda VAL
        sta COUNT
        lda VAL+1
        sta COUNT+1
        lda #0
        sta FILL
        jsr skip
        cmp #','
        bne @loop
        inc IDX
        jsr expression
        jsr byte_value
        sta FILL
@loop: lda COUNT
        ora COUNT+1
        beq @done
        lda FILL
        jsr emit
        lda COUNT
        bne :+
        dec COUNT+1
:      dec COUNT
        jmp @loop
@done: rts
end_source:
        inc EOFFLAG
        rts

byte_value:
        lda VAL+1
        beq @ok
        lda UNDEF
        bne @ok
        jmp err_range
@ok:   lda VAL
        rts

; Every pass advances PC and OUT identically; only pass two writes bytes.
emit:   sta EMITBYTE
        lda ORIGINSET
        jeq err_noorg
        lda OUT+1
        cmp #$84
        jcs err_output
        lda PASS
        beq @advance
        ldy #0
        lda EMITBYTE
        sta (OUT),y
@advance:
        inc OUT
        bne :+
        inc OUT+1
:      inc PC
        bne @done
        inc PC+1
        jeq err_range
@done: rts

; Operand modes: implied, accumulator, immediate, zp, zpX, zpY,
; absolute, absoluteX, absoluteY, indirect, (zp,X), (zp),Y, relative.
instruction:
        lda TOKLEN
        cmp #3
        jne err_opcode
        ldx #0
@mn:   lda mnemonics,x
        cmp TOKEN
        bne @next
        lda mnemonics+1,x
        cmp TOKEN+1
        bne @next
        lda mnemonics+2,x
        cmp TOKEN+2
        beq @found
@next: inx
        inx
        inx
        cpx #MNEMONIC_BYTES
        bcc @mn
        jmp err_opcode
@found: stx OP
        lda #0
        sta AMODE
        jsr skip
        jeq @lookup
        cmp #';'
        jeq @lookup
        jsr upper
        cmp #'A'
        bne @operand
        ldy IDX
        lda LINEBUF+1,y
        beq @acc
        cmp #';'
        beq @acc
        cmp #' '
        beq @acc
        cmp #9
        bne @operand
@acc:  inc IDX
        inc AMODE
        jmp @lookup
@operand:
        lda #12
        sta AMODE
        jsr lookup
        bcc @branch
        jsr peek
        cmp #'#'
        beq @imm
        cmp #'('
        jeq indirect
        jsr expression
        lda #6
        sta AMODE
        jsr index_suffix
        lda VAL+1
        bne @lookup
        lda FORCE               ; explicit < also fixes size for forward refs
        bne @tryzp
        lda UNDEF
        bne @lookup
        lda REF
        beq @tryzp
        lda FORCE
        jeq @lookup
@tryzp: lda AMODE
        pha
        sec
        sbc #3
        sta AMODE
        jsr lookup
        pla
        bcc @lookup
        sta AMODE
        jmp @lookup
@imm:  inc IDX
        jsr expression
        jsr byte_value
        lda #2
        sta AMODE
        jmp @lookup
@branch:
        jsr expression
        sec
        lda VAL
        sbc PC
        sta VAL
        lda VAL+1
        sbc PC+1
        sta VAL+1
        sec
        lda VAL
        sbc #2
        sta VAL
        lda VAL+1
        sbc #0
        sta VAL+1
        lda PASS
        jeq @lookup
        lda VAL
        cmp #$80
        lda VAL+1
        adc #0
        jne err_branch
@lookup:
operand_emit = *
        jsr lookup
        jcs err_mode
        lda opcode_bytes,x
        jsr emit
        ldx AMODE
        lda mode_size,x
        cmp #1
        beq @done
        lda VAL
        jsr emit
        ldx AMODE
        lda mode_size,x
        cmp #3
        bne @done
        lda VAL+1
        jsr emit
@done: rts

indirect:
        inc IDX
        jsr expression
        lda #9
        sta AMODE
        jsr skip
        cmp #','
        beq @inx
        cmp #')'
        jne err_syntax
        inc IDX
        jsr skip
        cmp #','
        bne @ready
        inc IDX
        jsr skip
        jsr upper
        cmp #'Y'
        jne err_syntax
        inc IDX
        lda #11
        bne @zp
@inx:  inc IDX
        jsr skip
        jsr upper
        cmp #'X'
        jne err_syntax
        inc IDX
        jsr skip
        cmp #')'
        jne err_syntax
        inc IDX
        lda #10
@zp:   sta AMODE
        jsr byte_value
@ready: jmp operand_emit

index_suffix:
        jsr skip
        cmp #','
        bne @done
        inc IDX
        jsr skip
        jsr upper
        cmp #'X'
        beq @x
        cmp #'Y'
        jne err_syntax
        inc AMODE
@x:    inc AMODE
        inc IDX
@done: rts

lookup: ldx #0
@loop: lda opcode_names,x
        cmp OP
        bne @next
        lda opcode_modes,x
        cmp AMODE
        beq @yes
@next: inx
        cpx #151
        bcc @loop
        sec
        rts
@yes:  clc
        rts
mode_size: .byte 1,1,2,2,2,2,3,3,3,3,2,2,2

; Native SAVE writes a load-address-prefixed mini6502 binary. The banked
; helper stages/restores fixed RAM; banked output uses an inactive image bank.
save_binary:
        lda BANK
        sta OLD_BANK
        lda ORIGIN+1
        cmp #$E0
        bcs @bank
        cmp #2
        jcc save_range
        clc
        lda ORIGIN
        adc LENGTH
        lda ORIGIN+1
        adc LENGTH+1
        cmp #$CC
        bcc @fixed
        jne save_range
        lda ORIGIN
        clc
        adc LENGTH
        jne save_range
@fixed: jsr $E009
        jmp save_status
@bank: cmp #$F0
        jcs save_range
        clc
        lda ORIGIN
        adc LENGTH
        sta DEND
        lda ORIGIN+1
        adc LENGTH+1
        sta DEND+1
        cmp #$F0
        bcc @stage
        jne save_range
        lda DEND
        jne save_range
@stage: lda #0
        sta DMASRC
        lda #$44
        sta DMASRC+1
        lda #$FF
        sta DMASRC+2
        lda ORIGIN
        sta DMADST
        lda IMAGEBANK
        and #$0F
        asl
        asl
        asl
        asl
        sta TMP
        lda ORIGIN+1
        and #$0F
        ora TMP
        sta DMADST+1
        lda IMAGEBANK
        lsr
        lsr
        lsr
        lsr
        sta DMADST+2
        lda LENGTH
        sta DMALEN
        lda LENGTH+1
        sta DMALEN+1
        lda #0
        sta DMALEN+2
        lda #1
        sta DMACMD
        lda ORIGIN
        sta DSTART
        lda ORIGIN+1
        sta DSTART+1
        lda #<$0350
        sta DNAME
        lda #>$0350
        sta DNAME+1
        lda $0340
        sta DNLEN
        lda IMAGEBANK
        sta BANK
        lda #2
        sta DCMD
        lda OLD_BANK
        sta BANK
        lda DSTAT
save_status:
        cmp #0
        bne @error
        lda #<msg_saved
        ldx #>msg_saved
        jmp message
@error: lda #<msg_disk
        ldx #>msg_disk
        jmp message
save_range:
        lda #<msg_save_range
        ldx #>msg_save_range
        jmp message

; All assembly errors unwind to the core caller, leaving editor state intact.
.macro ERROR name, text
name:   lda #<text
        ldx #>text
        jmp fail
.endmacro
ERROR err_syntax, msg_syntax
ERROR err_opcode, msg_opcode
ERROR err_mode, msg_mode
ERROR err_undefined, msg_undefined
ERROR err_duplicate, msg_duplicate
ERROR err_symbols_full, msg_symbols
ERROR err_symbol_long, msg_symbol_long
ERROR err_range, msg_range
ERROR err_branch, msg_branch
ERROR err_phase, msg_phase
ERROR err_forward, msg_forward
ERROR err_origin, msg_origin
ERROR err_noorg, msg_noorg
ERROR err_output, msg_output
ERROR err_longline, msg_longline
ERROR err_empty, msg_empty
fail:   pha
        lda #1
        sta RESULT
        lda LINE
        sta ERRLINE
        lda LINE+1
        sta ERRLINE+1
        pla
        jsr message
        ldx SAVEDSP
        txs
        rts
message:
        sta SPTR
        stx SPTR+1
        ldy #0
@copy: lda (SPTR),y
        sta MESSAGE,y
        beq @done
        iny
        bne @copy
@done: rts

dirs_lo: .lobytes dir_org,dir_byte,dir_word,dir_text,dir_res,dir_end
dirs_hi: .hibytes dir_org,dir_byte,dir_word,dir_text,dir_res,dir_end
dirs_jump: .word org-1,data_bytes-1,data_words-1,data_bytes-1,reserve-1,end_source-1
dir_org: .byte ".ORG",0
dir_byte: .byte ".BYTE",0
dir_word: .byte ".WORD",0
dir_text: .byte ".TEXT",0
dir_res: .byte ".RES",0
dir_end: .byte ".END",0
msg_ok: .byte " Assembled OK (binary not saved)",0
msg_saved: .byte " Assembled and saved binary",0
msg_disk: .byte " Disk error saving binary",0
msg_save_range: .byte " Save range: $0200-$CBFF or one $E000-$EFFF bank",0
msg_syntax: .byte " Syntax error",0
msg_opcode: .byte " Unknown instruction or directive",0
msg_mode: .byte " Invalid addressing mode",0
msg_undefined: .byte " Undefined symbol",0
msg_duplicate: .byte " Duplicate symbol",0
msg_symbols: .byte " Symbol table full (256)",0
msg_symbol_long: .byte " Symbol too long (15 characters)",0
msg_range: .byte " Value out of range",0
msg_branch: .byte " Branch out of range (-128..127)",0
msg_phase: .byte " Phase error (address changed between passes)",0
msg_forward: .byte " Forward reference in constant, origin or reserve size",0
msg_origin: .byte " Origin cannot move backwards",0
msg_noorg: .byte " Set .ORG before emitting code",0
msg_output: .byte " Output exceeds 16384 bytes",0
msg_longline: .byte " Source line exceeds 254 characters",0
msg_empty: .byte " No bytes assembled",0
        .include "opcodes.inc"
        .assert * <= $B000, error, "assembler overlaps symbol table"
