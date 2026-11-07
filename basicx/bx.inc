; bx.inc - for writing mini6502 BASIC extensions
; Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
; personal, non-commercial use only (see basic/README.txt).
; mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.
; An extension is a 4K bank image for one of banks $00-$07:
;   $E000  "BX", version (2; 1 = an older one without $E014 / $E016)
;   $E003  JMP statement  a "!" statement: A = its first character after
;                         the "!", the line pointer on it. Your keyword:
;                         run it, return with carry clear (the line pointer
;                         at the end of the statement). Not yours: carry
;                         set and the line pointer untouched.
;   $E006  JMP init       called at every BASIC cold and warm start
;   $E009  JMP function   a "!" in an expression: the same, but return its
;                         value in Y (low) / A (high), signed, carry clear
;                         (no functions: SEC, RTS)
;   $E00C  your name: 8 bytes, 0 after it (and padding with 0)
;   $E014  .word your commands' keyword list (as for XMATCH), for !HELP
;   $E016  .word your functions' keyword list, or 0
; !HELP lists every extension loaded, from these. Answer it yourself with
; bxhelp.inc (jmp bxhelp): whichever extension answers first lists them all.
; BASIC's own zero page is busy; $F0-$F7 belong to bxmatch.inc, $F8-$FF are
; yours. Errors (yours or BASIC's) put the program's bank back by themselves.

; the API (fixed addresses in BASIC)
XCHRGET  = $A009        ; next character of the line: A (Z set at ":" / end)
XCHRGOT  = $A00C        ; the current character again
XGETBYTE = $A00F        ; a 0-255 expression: X (A = the character after)
XCOMMA   = $A012        ; a "," (else Syntax error)
XGETWORD = $A015        ; a numeric expression: its low 16 bits in Itempl/h
XGETSTR  = $A018        ; a string expression: A = length, X/Y = its address
XGETVAR  = $A01B        ; the numeric variable named here: XSETVAR sets it
XSETVAR  = $A01E        ; that variable = Y (low) / A (high), signed
XERROR   = $A021        ; error X (ERR_ below), then Ready
XKEYT    = $A024        ; (2 bytes) BASIC's keyword table, for bxmatch.inc
XDISK    = $A027        ; disk command A with bank X selected meanwhile;
                        ; a failure gives BASIC's disk error message
XPRINT   = $A02A        ; print the character A
XCRLF    = $A02D        ; new line
XGETNUM  = $A030        ; a numeric expression into FAC1
XSYNTAX  = $A033        ; Syntax error
XFUNC    = $A036        ; Function call error (a value out of range)

; BASIC's zero page and RAM that extensions may use
Bpntrl   = $C3          ; the line pointer (2 bytes)
Bpntrh   = $C4
Itempl   = $11          ; XGETWORD's result (2 bytes)
Itemph   = $12
TPos     = $0E          ; the terminal column BASIC thinks the cursor is in
XBANK    = $0311        ; the bank the program had selected

; error codes for XERROR
ERR_SN   = $02          ; Syntax
ERR_FC   = $08          ; Function call
ERR_OV   = $0A          ; Overflow
ERR_OM   = $0C          ; Out of memory
ERR_TM   = $18          ; Type mismatch
