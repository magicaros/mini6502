# ASM — native mini6502 assembler and editor

ASM is a banked full-screen source editor based on EDIT, with a native
two-pass NMOS 6502 assembler. Assembly happens on the emulated 6502; Python
and cc65 are only needed to rebuild or test the application on the host.

The disk's `ASM/` folder contains `ASM`, `ASMCORE`, and `HELLO.ASM`.
ASM loads `/ASM/ASMCORE` on demand into its private RAM, independently of
the current disk folder. This matches the desktop's `/ASM/ASM` launcher.

## Start and use

From the monitor:

```text
P /ASM
L ASM E000 20
D020: 20
E000R
```

From that folder, use Ctrl+L to open `HELLO.ASM`, then **Ctrl+A** to assemble. On success,
enter a binary filename such as `HELLO`. Esc cancels saving without losing
the source. Ctrl+S saves the **source**, independently of Ctrl+A's binary
output. A binary cannot overwrite the currently named source file.

Esc returns to the caller with its RAM restored. Run the example:

```text
L HELLO
0300R
```

Re-select bank `$20` and use `E003R` to resume the editor. `$E000` starts
fresh; `$E006` opens the zero-terminated filename supplied at `$EF80`,
matching EDIT and the desktop's existing ASM application interface. Load
ASM into a nonzero bank below `$80`, normally `$20`; source and caller
preservation require 13 contiguous free document banks. No boot script or
far-call vector change is needed.

Editing keys are EDIT's: arrows, Home/End, PgUp/PgDn, Enter, Backspace,
Delete and Tab; Ctrl+N new, Ctrl+L load, Ctrl+S save, Esc return. Errors
show a line number and message, and move the cursor to that source line.
An unsaved source buffer can be assembled directly.

## Syntax

Instructions and symbols are case-insensitive. Labels end in `:`;
constants use `NAME = expression`. Symbols have up to 15 characters,
starting with a letter or underscore; following characters may include
digits. Labels may share a line with an instruction. `;` starts a comment
outside strings. Use `A` explicitly for accumulator shifts/rotates.

All 151 official NMOS 6502 opcodes/addressing combinations are supported,
including `(zp,X)`, `(zp),Y`, `JMP (address)`, and relative branches.
65C02 extensions and undocumented opcodes are not supported.

Expressions accept `$hex`, `%binary`, decimal, `'c'`, symbols, `*` (current
address), unary `+`/`-`, `<` (low byte), `>` (high byte), and left-to-right
addition/subtraction. Arithmetic uses 16-bit values; literal overflow and
out-of-range byte/branch operands are errors. There are no grouped
expressions, multiplication, escapes, includes, macros or local scopes.
`<`/`>` apply to the following atom, before addition/subtraction.

Numeric addresses use zero-page encodings where available. **Symbolic
memory operands use absolute encodings**, keeping forward-reference sizes
stable between passes. Prefix a symbol with `<` to explicitly choose its
low byte and zero-page encoding. For example:

```asm
PORT = $D012
PTR = $20
.org $0300
start:  lda #<message
        sta <PTR
        lda #>message
        sta <PTR+1
        lda message
        sta PORT
        rts
message: .byte "Hello",13,0
```

| Directive | Meaning |
| --- | --- |
| `.org expression` or `* = expression` | Set origin; subsequent forward gaps are zero-filled. |
| `.byte expression,...` | Bytes and/or double-quoted ASCII strings. |
| `.text "text",...` | Same as `.byte`. |
| `.word expression,...` | Little-endian 16-bit values. |
| `.res count[,fill]` | Reserve bytes, default fill zero. |
| `.end` | Stop processing source. |

Set an origin before emitting bytes. Origins cannot move backwards.
Constants, origins and reserve counts must resolve when first seen;
instruction/data operands may refer forward to labels. Binary files have
the standard two-byte load address followed by the emitted data. Saving
supports fixed RAM `$0200-$CBFF`, or a single bank range `$E000-$EFFF`.
Other targets produce a save-range message; ROM, I/O and the system page
are protected. Banked binaries can subsequently be loaded into any suitable
bank with the monitor's `L name E000 bank` command.

## Memory and limits

| Area | Use |
| --- | --- |
| `$0400-$43FF` | 16 KiB source gap buffer |
| `$4400-$83FF` | Up to 16 KiB assembled output |
| `$8400-$AFFF` | On-demand core and reserved space |
| `$B000-$C3FF` | Up to 256 symbols (20 bytes each) |
| `$C400-$C7FF` | Results, messages, line and token buffers |
| `$CBF0` | EDIT-compatible warm-start stub |
| Application bank `$E000-$EFFF` | Editor, disk-save helper, entry state |
| 13 allocated banks in `$80-$BF` | Persistent private RAM image |
| `$F0-$FC` | Caller RAM while ASM runs, as in EDIT |

Source lines may contain up to 254 characters. Source files use EDIT's
load-address-prefixed text format and normalize CR/LF on load. The private
image is separate from EDIT's `$E0-$EC` image. As with EDIT, the standard
caller swap area must not be used by another nested editor while ASM runs.
F1 followed by G resumes ASM; Esc restores the original caller's G address.
The banked application owns its allocated image until that owner is freed;
manual monitor use retains it for warm re-entry.

Binary saving temporarily stages data at the requested address and restores
the source, core and caller state. Bank output is staged in an inactive
image bank, so it never overwrites ASM's executing editor bank. Assembly
does not run the generated program automatically.

## Build and test

```sh
sh asm/build.sh                 # outputs asm/build/ASM and ASMCORE
mkdir -p disk/ASM
cp asm/build/ASM disk/ASM/ASM
cp asm/build/ASMCORE disk/ASM/ASMCORE
cp asm/build/HELLO.ASM disk/ASM/HELLO.ASM
python3 asm/test_asm.py          # requires py65 and Pillow, plus ca65/ld65
```

The tests execute the actual native binaries using the existing mini6502
bus/simulator. They cover all official opcodes, forward references, gap
positions, error paths, disk output, source/caller preservation, and editor
entry/resume. The normal EDIT build remains byte-for-byte unchanged.
