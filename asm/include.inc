; Include files are disk text (two-byte load header + source). Pass one
; stages each file in the unused output buffer, then caches it in 16
; allocated document banks. Pass two reads that snapshot without disk I/O.

include_init:
        lda #0
        sta ICACHE
        sta IUSED
        sta IUSED+1
        sta IFILES
        sta IACTIVE
        ; Resolve the main source's name against WHERE, without changing CWD.
        lda #<IRAW
        sta DSTART
        lda #>IRAW
        sta DSTART+1
        lda #<i_empty
        sta DNAME
        lda #>i_empty
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #13
        sta DCMD
        lda DSTAT
        jne err_include_disk
        ldx #0
@cwd:  lda IRAW,x
        beq @separator
        inx
        bne @cwd
@separator:
        cpx #191
        jcs err_include_path
        lda #'/'
        sta IRAW,x
        inx
        ldy #0
        lda $0302              ; EDIT's current source name length
        beq @buffer
        lda $0310
        cmp #'/'
        bne @name
        ldx #0
@name: cpy $0302
        beq @end
        cpx #191
        jcs err_include_path
        lda $0310,y
        sta IRAW,x
        inx
        iny
        bne @name
@buffer:
        ldy #0                 ; placeholder cannot collide with a disk filename
@unnamed:
        lda i_buffer,y
        beq @end
        sta IRAW,x
        inx
        iny
        bne @unnamed
@end:  lda #0
        sta IRAW,x
        jsr include_normalize
        ldx #0
@copy: lda IPATH,x
        sta IROOT,x
        beq @done
        inx
        bne @copy
@done: rts

; A is the zero-based descriptor number. IREC = ITABLE + A*208.
include_record:
        tax
        lda #<ITABLE
        sta IREC
        lda #>ITABLE
        sta IREC+1
        cpx #0
        beq @done
@add:  clc
        lda IREC
        adc #208
        sta IREC
        bcc :+
        inc IREC+1
:       dex
        bne @add
@done: rts

; Parse and validate before switching streams: the outer trailing check
; still sees this directive's original line. Paths are always absolute.
include_source:
        jsr skip
        cmp #'"'
        jne err_syntax
        inc IDX
        lda IACTIVE
        beq @root
        sec
        sbc #1
        jsr include_record
        lda IREC
        ldx IREC+1
        jmp @parent
@root: lda #<IROOT
        ldx #>IROOT
@parent:
        sta IPTR
        stx IPTR+1
        ldy #0
        ldx #0
@prefix:
        lda (IPTR),y
        beq @copy_prefix
        cmp #'/'
        bne :+
        tya
        tax                    ; last slash in containing source's path
:       iny
        bne @prefix
@copy_prefix:
        inx
        stx IINDEX
        ldy #0
@copy: cpy IINDEX
        beq @literal
        lda (IPTR),y
        sta IRAW,y
        iny
        bne @copy
@literal:
        jsr peek
        cmp #'/'
        bne @char
        ldx #0                 ; absolute include ignores containing directory
@char: jsr peek
        jeq err_syntax
        cmp #'"'
        beq @close
        cpx #191
        jcs err_include_path
        sta IRAW,x
        inx
        inc IDX
        jmp @char
@close:
        ; Empty quoted names must not resolve to their containing folder.
        ldy IDX
        lda LINEBUF-1,y
        cmp #'"'
        jeq err_include_path
        lda #0
        sta IRAW,x
        inc IDX
        jsr trailing
        jsr include_normalize
        jsr include_cycle
        lda IDEPTH
        cmp #4
        jcs err_include_depth
        lda ISEQ
        cmp #16
        jcs err_include_count
        jsr include_record
        lda PASS
        jne @cached
        lda ICACHE
        bne @load
        lda BANK
        ldx #16
        ldy #1
        jsr BALLOC
        jcs err_include_memory
        sta ICACHE
@load: lda #<IPATH
        sta DNAME
        lda #>IPATH
        sta DNAME+1
        lda #0
        sta DNLEN
        sta DSTART
        sta DEND
        lda #$44
        sta DSTART+1
        lda #$84
        sta DEND+1
        lda #3
        sta DCMD
        lda DSTAT
        beq @loaded
        cmp #1
        jeq err_include_missing
        cmp #3
        jeq err_include_size
        jmp err_include_disk
@loaded:
        sec
        lda DEND
        sbc #0
        sta DMALEN
        lda DEND+1
        sbc #$44
        sta DMALEN+1
        lda #0
        sta DMALEN+2
        clc
        lda IUSED
        adc DMALEN
        sta IPTR
        lda IUSED+1
        adc DMALEN+1
        sta IPTR+1
        jcs err_include_cache
        lda IUSED
        sta DMADST
        lda ICACHE
        and #$0F
        asl
        asl
        asl
        asl
        clc
        adc IUSED+1
        sta DMADST+1
        php
        lda ICACHE
        lsr
        lsr
        lsr
        lsr
        plp
        adc #0
        sta DMADST+2
        lda #0
        sta DMASRC
        lda #$44
        sta DMASRC+1
        lda #$FF
        sta DMASRC+2
        ; Empty includes do not trigger a zero-length DMA.
        lda DMALEN
        ora DMALEN+1
        beq @descriptor
        lda #1
        sta DMACMD
@descriptor:
        ldy #0
@path: lda IPATH,y
        sta (IREC),y
        beq @address
        iny
        bne @path
@address:
        ldy #192
        lda DMADST
        sta (IREC),y
        iny
        lda DMADST+1
        sta (IREC),y
        iny
        lda DMADST+2
        sta (IREC),y
        iny
        lda DMALEN
        sta (IREC),y
        iny
        lda DMALEN+1
        sta (IREC),y
        lda IPTR
        sta IUSED
        lda IPTR+1
        sta IUSED+1
        inc IFILES
        jmp @enter
@cached:
        lda ISEQ
        cmp IFILES
        jcs err_phase
        jsr include_path_equal
        jcs err_phase
@enter:
        jsr include_push
        inc ISEQ
        lda ISEQ
        sta IACTIVE
        ldy #192
        lda (IREC),y
        sta IADDR
        iny
        lda (IREC),y
        sta IADDR+1
        iny
        lda (IREC),y
        sta IADDR+2
        iny
        lda (IREC),y
        sta ILEFT
        iny
        lda (IREC),y
        sta ILEFT+1
        lda #0                 ; main loop increments the child's line to 1
        sta LINE
        sta LINE+1
        sta IPREVCR
        rts

include_push:
        lda IDEPTH
        asl
        asl
        asl
        asl
        tax
        lda SRC
        sta IFRAMES,x
        lda SRC+1
        sta IFRAMES+1,x
        lda IADDR
        sta IFRAMES+2,x
        lda IADDR+1
        sta IFRAMES+3,x
        lda IADDR+2
        sta IFRAMES+4,x
        lda ILEFT
        sta IFRAMES+5,x
        lda ILEFT+1
        sta IFRAMES+6,x
        lda IACTIVE
        sta IFRAMES+7,x
        bne @line
        lda LINE
        sta INAVLINE
        lda LINE+1
        sta INAVLINE+1
@line: lda LINE
        sta IFRAMES+8,x
        lda LINE+1
        sta IFRAMES+9,x
        lda IPREVCR
        sta IFRAMES+10,x
        inc IDEPTH
        rts

include_pop:
        dec IDEPTH
        lda IDEPTH
        asl
        asl
        asl
        asl
        tax
        lda IFRAMES,x
        sta SRC
        lda IFRAMES+1,x
        sta SRC+1
        lda IFRAMES+2,x
        sta IADDR
        lda IFRAMES+3,x
        sta IADDR+1
        lda IFRAMES+4,x
        sta IADDR+2
        lda IFRAMES+5,x
        sta ILEFT
        lda IFRAMES+6,x
        sta ILEFT+1
        lda IFRAMES+7,x
        sta IACTIVE
        lda IFRAMES+8,x
        sta LINE
        lda IFRAMES+9,x
        sta LINE+1
        lda IFRAMES+10,x
        sta IPREVCR
        inc LINE               ; resume after the parent's include directive
        bne @done
        inc LINE+1
@done: rts

; Lexically canonicalize absolute paths (/, repeated /, ., ..), preserving
; case for disk lookup. No host paths or disk current-folder changes.
include_normalize:
        lda #'/'
        sta IPATH
        ldx #1
        ldy #0
@next: lda IRAW,y
        beq @done
        cmp #'/'
        bne @component
        iny
        bne @next
@component:
        cpx #1
        beq :+
        lda #'/'
        sta IPATH,x
        inx
:       stx ICOMP
@char: lda IRAW,y
        beq @special
        cmp #'/'
        beq @special
        cpx #191
        jcs err_include_path
        sta IPATH,x
        inx
        iny
        bne @char
@special:
        txa
        sec
        sbc ICOMP
        cmp #1
        beq @dot
        cmp #2
        bne @next
        stx IINDEX
        ldx ICOMP
        lda IPATH,x
        cmp #'.'
        bne @restore
        lda IPATH+1,x
        cmp #'.'
        bne @restore
        cpx #1
        jeq err_include_path
        dex
@parent:
        cpx #1
        beq @next
        dex
        lda IPATH,x
        cmp #'/'
        bne @parent
        jmp @next
@restore:
        ldx IINDEX
        jmp @next
@dot:  stx IINDEX
        ldx ICOMP
        lda IPATH,x
        cmp #'.'
        bne @restore
        cpx #1
        beq @next
        dex
        jmp @next
@done: lda #0
        sta IPATH,x
        rts

; Compare candidate IPATH against IREC's path, ignoring ASCII case.
include_path_equal:
        ldy #0
@char: lda (IREC),y
        jsr upper
        sta ICOMP
        lda IPATH,y
        jsr upper
        cmp ICOMP
        bne @no
        cmp #0
        beq @yes
        iny
        bne @char
@no:   sec
        rts
@yes:  clc
        rts

include_cycle:
        lda #<IROOT
        sta IREC
        lda #>IROOT
        sta IREC+1
        jsr include_path_equal
        jcc err_include_cycle
        lda IACTIVE
        beq @done
        sec
        sbc #1
        jsr include_record
        jsr include_path_equal
        jcc err_include_cycle
        lda #0
        sta IINDEX
@frame: lda IINDEX
        cmp IDEPTH
        bcs @done
        asl
        asl
        asl
        asl
        tax
        lda IFRAMES+7,x
        beq @next
        sec
        sbc #1
        jsr include_record
        jsr include_path_equal
        jcc err_include_cycle
@next: inc IINDEX
        jmp @frame
@done: rts

include_cleanup:
        lda ICACHE
        beq @done
        ldy #0
@free: tya
        clc
        adc ICACHE
        jsr BFREE
        iny
        cpy #16
        bcc @free
        lda #0
        sta ICACHE
@done: rts

; Included-source errors keep ERRLINE at the root include site. Add the
; included basename and local line to the status message (bounded to 79).
include_diagnostic:
        lda IACTIVE
        beq @done
        sec
        sbc #1
        jsr include_record
        ldx #0
@save: lda MESSAGE,x
        sta IRAW,x
        beq @path
        inx
        bne @save
@path: lda #0
        sta FBINDEX
        sta FBCOUNT
        ldy #0
        ldx #0
@scan: lda (IREC),y
        beq @basename
        cmp #'/'
        bne :+
        tya
        tax
        inx
:       iny
        bne @scan
@basename:
        txa
        tay
@name: lda (IREC),y
        beq @line
        jsr fb_char
        iny
        inc FBCOUNT
        lda FBCOUNT
        cmp #24
        bcc @name
@line: lda #':'
        jsr fb_char
        lda LINE
        ldx LINE+1
        jsr fb_number
        lda #':'
        jsr fb_char
        lda ERRCOL
        ldx #0
        jsr fb_number
        lda #' '
        jsr fb_char
        lda #<IRAW
        ldx #>IRAW
        jsr fb_string
        jmp fb_finish
@done: rts

ERROR err_include_missing, i_missing
ERROR err_include_size, i_size
ERROR err_include_disk, i_disk
ERROR err_include_memory, i_memory
ERROR err_include_cache, i_cache
ERROR err_include_count, i_count
ERROR err_include_depth, i_depth
ERROR err_include_cycle, i_cycle
ERROR err_include_path, i_path
i_empty: .byte 0
i_buffer: .byte "<buffer>",0
i_missing: .byte " Include file not found",0
i_size: .byte " Include file exceeds 16384 bytes",0
i_disk: .byte " Include disk error",0
i_memory: .byte " No room for include cache (16 banks)",0
i_cache: .byte " Include cache exceeds 65535 bytes",0
i_count: .byte " Too many includes (16)",0
i_depth: .byte " Includes nested too deeply (4)",0
i_cycle: .byte " Recursive include",0
i_path: .byte " Invalid or overlong include path",0
i_tens_lo: .lobytes 10000,1000,100,10,1
i_tens_hi: .hibytes 10000,1000,100,10,1
