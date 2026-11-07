;=============================================================================
; desk.inc - mini6502 desktop: definitions shared by its two banks
;=============================================================================

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

        .include "../toolkit/tk.inc"

DESKBANK1 = $14         ; desk1.asm: main loop, the disk window, launching
DESKBANK2 = $15         ; desk2.asm: menus, dialogs, clock, calculator
DESKBANK3 = $16         ; desk3.asm: the icons
LAUNCHBANK = $20        ; programs from the disk are loaded here
SAVEBANK  = $C0         ; the desktop's RAM while a program runs ($C0-$CC)

TOOL    = $CC88         ; far-call entry 16: the toolkit
DESKENT = $CC90         ; far-call entry 17: the desktop (CALL $CC90)
; far-call entries 18-24 ($CC98-$CCCF) are the desktop's own stubs:
RESUME  = $CC98         ; JSR $FFD0 / DESKBANK1 / resume   (the G command)
LAUNCH  = $CCA0         ; JSR TARGET / LDA #DESKBANK1 / STA BANK / JMP RESUME
TARGET  = $CCB0         ; JMP entry, or JSR $FFD0 / bank / entry
BANKLD  = $CCB8         ; LDA #bank / STA BANK / LDA #3 / STA DCMD /
                        ; LDA #DESKBANK1 / STA BANK / RTS


; file kinds (and icons)
K_DATA  = 0
K_TEXT  = 1
K_BASIC = 2
K_PROG  = 3             ; machine code in the main RAM: entry = load address
K_APP   = 4             ; machine code for a bank ($E000)
K_SYS   = 5             ; the toolkit and the desktop themselves, VECTORS
K_FOLDER = 7            ; a folder (icon 7; 6 is the Disk icon)
K_MUSIC = 8             ; a song (.MUS): opens in TRACKER
K_PICT  = 9             ; a picture (.PIC): opens in PAINT
K_PIX   = 10            ; a pixel picture (.PIX): opens in PIXEL
K_ASM   = 11            ; 6502 source (.ASM): ASM, or else NOTE

; fixed RAM (the desktop's while it runs; saved while a program runs)
DIRBUF  = $0800         ; DIR into memory ($0800-$0FFF)
DIREND  = $1000
FNL     = $1000         ; name address, low / high (64 + 64)
FNH     = $1040
FKIND   = $1080
FSZL    = $10C0         ; size
FSZH    = $1100
FLDL    = $1140         ; load address
FLDH    = $1180
NFILES  = $11C0
SCRATCH = $C300         ; strings built for dialogs and scripts
NAMEBUF = $C400         ; RENAME's answer
PATHA   = $C500         ; the current folder's path (WHERE), 132 bytes
TITLEB  = $C590         ; the Disk window's title, 32
SRCP    = $C5B0         ; Copy / Move: the file's path, 200
DSTP    = $C680         ; Copy / Move: where it goes, 200
MAXFILE = 64

; zero page ($80-$FF is the program's)
DP      = $80           ; pointer
DQ      = $82
D0      = $84           ; temporaries
D1      = $86
D2      = $88
D3      = $8A
ORGX    = $8C           ; contents of the window being drawn
ORGY    = $8E
CX      = $90
CY      = $92
IDX     = $94
NUM     = $96           ; 4 bytes

.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro
