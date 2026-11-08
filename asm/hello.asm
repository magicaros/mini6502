; Assemble inside mini6502 with Ctrl+A, save as HELLO, then Esc.
; From the monitor: L HELLO, then 0300R.
.org $0300
start:
        ldx #0
loop:
        lda message,x
        beq done
        sta $D012
        inx
        bne loop
done:
        rts
message:
        .byte "HELLO FROM ASM!",13,0
