"""Execute the native assembler on the repository's mini6502 bus and py65 CPU.

Run: python3 asm/test_asm.py (requires py65 and Pillow; builds with ca65/ld65).
"""
import contextlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'asm/build'
subprocess.run(['sh', str(ROOT / 'asm/build.sh')], check=True)
_disk = tempfile.TemporaryDirectory()
os.environ['SIMDISK'] = _disk.name
os.environ['SIMCOLD'] = '0'
sys.argv = ['simtest.py', str(Path(__import__('py65').__file__).parent.parent),
            str(ROOT / 'monitor/monitor.bin'), '--cycles', '0']
with contextlib.redirect_stdout(io.StringIO()):
    SIM = runpy.run_path(str(ROOT / 'monitor/simtest.py'))
from py65.devices.mpu6502 import MPU


class Machine:
    def __init__(self):
        SIM['disk'].__globals__['CUR'].clear()
        self.bus = SIM['Bus']()
        self.cpu = MPU(memory=self.bus)
        self.bus.__class__.__getitem__.__globals__['cpu'] = self.cpu
        rom = (ROOT / 'monitor/monitor.bin').read_bytes()
        self.bus.m[65536 - len(rom):] = rom
        self.bus.bank = 0x20
        self.bus.banks[0x20000:0x20000 + len((BUILD/'asm.bin').read_bytes())] = (BUILD/'asm.bin').read_bytes()
        self.bus.m[0x8400:0x8400 + len((BUILD/'core.bin').read_bytes())] = (BUILD/'core.bin').read_bytes()
        self.bus.m[0xc407] = 0x80
        self.labels = dict((s[2].lstrip('.'), int(s[1],16))
                           for ln in (BUILD/'asm.labels').read_text().splitlines()
                           if len(s:=ln.split())==3)

    def word(self, address, value=None):
        if value is not None:
            self.bus.m[address:address+2] = value.to_bytes(2, 'little')
        return int.from_bytes(self.bus.m[address:address+2], 'little')

    def call(self, address, max_steps=5000000):
        self.cpu.sp = 0xff
        self.cpu.stPushWord(0x01ff)  # RTS returns to $0200
        self.cpu.pc = address
        for _ in range(max_steps):
            self.cpu.step()
            if self.cpu.pc == 0x0200:
                return
        raise AssertionError(f'timeout PC=${self.cpu.pc:04X}')

    def assemble(self, source, gap=None, max_steps=5000000):
        data = source.replace('\r\n', '\n').replace('\n', '\r').encode('ascii')
        if gap is None:
            gap = len(data)
        self.bus.m[0x0400:0x0400+gap] = data[:gap]
        end = 0x4400 - (len(data)-gap)
        self.bus.m[end:0x4400] = data[gap:]
        self.word(0x10, 0x0400+gap)
        self.word(0x12, end)
        self.call(0x8400, max_steps=max_steps)
        msg = bytes(self.bus.m[0xc500:0xc580]).split(b'\0')[0].decode()
        return self.bus.m[0xc400], msg, bytes(self.bus.m[0x4400:0x4400+self.word(0xc405)])

    def save(self, filename='TESTBIN'):
        name = filename.encode()
        self.bus.m[0x340] = len(name)
        self.bus.m[0x350:0x350+len(name)] = name
        self.call(0x8403)
        return Path(_disk.name, filename)

    def editor(self, keys, entry=0xe000, pause=False):
        app = Path(_disk.name)/'ASM'
        app.mkdir(exist_ok=True)
        (app/'ASMCORE').write_bytes((BUILD/'ASMCORE').read_bytes())
        self.bus.queue = list(keys.replace('\n', '\r').encode('ascii'))
        self.cpu.sp = 0xff
        self.cpu.stPushWord(0x01ff)
        self.cpu.pc = entry
        for _ in range(5000000):
            self.cpu.step()
            if self.cpu.pc == 0x0200:
                return
            if pause and not self.bus.queue and self.cpu.pc == self.labels['getkey']:
                return
        raise AssertionError(f'editor timeout PC=${self.cpu.pc:04X}')

    def type_keys(self, keys):
        self.bus.queue = list(keys.replace('\n', '\r').encode('ascii'))
        for _ in range(5000000):
            self.cpu.step()
            if not self.bus.queue and self.cpu.pc == self.labels['getkey']:
                return
        raise AssertionError(f'editor timeout PC=${self.cpu.pc:04X}')


class AssemblerTests(unittest.TestCase):
    def test_assembly_summary_and_save_outcomes(self):
        m = self.assert_code('.org $0300\nstart: lda #42\nsta $0400\nrts', 'a9 2a 8d 00 04 60')
        def message():
            return bytes(m.bus.m[0xc500:0xc550]).split(b'\0')[0].decode()
        self.assertEqual(message(), ' Assembled: 6 bytes at $0300-$0305 | symbols: 1 | not saved')
        self.assertEqual(bytes(m.bus.m[0xc480:0xc4d0]).split(b'\0')[0],
                         b' $0300-$0305 6B 1sym Save: ')
        # Patch the normal editor save-helper ABI for this direct core call.
        for label, offsets in [('d_keep',(4,5)),('d_load',(1,2))]:
            for off,v in zip(offsets,[0,8]):
                m.bus.banks[0x20000+m.labels[label]-0xe000+off] = v
        m.save('SUMMARYBIN')
        self.assertEqual(message(), ' Saved: 6 bytes at $0300-$0305 | symbols: 1')
        (Path(_disk.name)/'SUMMARYFAIL').mkdir(exist_ok=True)
        m.save('SUMMARYFAIL')
        self.assertIn('Disk error; not saved: 6 bytes', message())
        m = self.assert_code('.org $d000\nnop', 'ea')
        m.save('RANGEFAIL')
        self.assertIn('Invalid save range; not saved: 1 byte at $D000-$D000',
                      bytes(m.bus.m[0xc500:0xc550]).split(b'\0')[0].decode())
        self.assertFalse((Path(_disk.name)/'RANGEFAIL').exists())

    def test_summary_handles_full_output_and_symbol_table(self):
        m = Machine()
        source = ''.join(f's{i} = {i}\n' for i in range(256)) + '.org $300\n.res 16384'
        status, message, body = m.assemble(source, max_steps=10000000)
        self.assertEqual(status, 0, message)
        self.assertEqual(len(body), 16384)
        self.assertIn('16384 bytes at $0300-$42FF | symbols: 256', message)
        prompt = bytes(m.bus.m[0xc480:0xc4d0]).split(b'\0')[0]
        self.assertEqual(prompt, b' $0300-$42FF 16384B 256sym Save: ')
        self.assertLessEqual(len(prompt)+40, 79)

    def test_editor_summary_prompt_cancel_and_saved_status(self):
        m = Machine()
        source = '.org $300\nstart: lda #42\nrts\n'
        m.editor(source+'\x01', pause=True)
        row = ''.join(map(chr,m.bus.g[24]))
        self.assertIn('$0300-$0302 3B 1sym Save:', row)
        m.type_keys('\x1b')
        row = ''.join(map(chr,m.bus.g[24]))
        self.assertIn('Assembled: 3 bytes at $0300-$0302', row)
        self.assertIn('symbols: 1 | not saved', row)
        m.type_keys('\x01FEEDBACKBIN\r')
        row = ''.join(map(chr,m.bus.g[24]))
        self.assertIn('Saved: 3 bytes at $0300-$0302 | symbols: 1', row)
        self.assertEqual((Path(_disk.name)/'FEEDBACKBIN').read_bytes(), bytes.fromhex('00 03 a9 2a 60'))

    def test_diagnostic_names_columns_and_cursor(self):
        for source, text, column in [('.org $300\nlda missing', 'Undefined symbol: MISSING',5),
                                     ('.org $300\n  wat #1', 'Unknown instruction or directive: WAT',3),
                                     ('.org $300\nx: nop\nx: rts', 'Duplicate symbol: X',1)]:
            with self.subTest(text=text):
                m = Machine()
                status, message, _ = m.assemble(source)
                self.assertEqual(status, 1)
                self.assertIn(text, message)
                self.assertEqual(m.bus.m[0xc412], column)
        m = Machine()
        m.editor('.org $300\n  lda missing\n\x01', pause=True)
        row = ''.join(map(chr,m.bus.g[24]))
        self.assertIn('Line 2 col 7', row)
        self.assertIn('Undefined symbol: MISSING', row)
        self.assertEqual(m.bus.cx, 6)
        self.assertEqual(m.word(0x16), 1)
        m = Machine()
        status, message, _ = m.assemble('.org $300\n;'+'x'*254)
        self.assertEqual(status, 1)
        self.assertIn('exceeds 254', message)
        self.assertEqual(m.bus.m[0xc412], 255)
    def include_file(self, name, text):
        p = Path(_disk.name, name)
        p.parent.mkdir(parents=True, exist_ok=True)
        body = text.encode('ascii') if isinstance(text, str) else text
        p.write_bytes(b'\x00\x04' + body)
        return p

    def test_includes_nested_paths_and_forward_labels(self):
        self.include_file('INC/outer.inc', '.include "./inner.inc"\r\n.byte <later\r\n')
        self.include_file('INC/inner.inc', 'VALUE = 42\nlda #VALUE')
        m = self.assert_code('.org $0300\n.include "INC/outer.inc"\nlater: rts\n', 'a9 2a 03 60')
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf90]), bytes(16))

    def test_include_paths_relative_to_named_main_source(self):
        self.include_file('PROJECT/defs.inc', 'PORT = $D012\n')
        self.include_file('SHARED/value.inc', '.byte 7\n')
        m = Machine()
        name = b'/PROJECT/main.asm'
        m.bus.m[0x302] = len(name)
        m.bus.m[0x310:0x310+len(name)] = name
        status, message, body = m.assemble('.include "defs.inc"\n.org $300\n'
                                           'sta PORT\n.include "../SHARED/value.inc"\nrts')
        self.assertEqual(status, 0, message)
        self.assertEqual(body, bytes.fromhex('8d 12 d0 07 60'))
        self.assertEqual(SIM['disk'].__globals__['CUR'], [])

    def test_include_diagnostics_and_recursion(self):
        self.include_file('ERRORS/bad.inc', '; first\r\nlda missing\r\n')
        m = Machine()
        status, message, _ = m.assemble('.org $300\n.include "/ERRORS/bad.inc"\nrts')
        self.assertEqual(status, 1)
        self.assertIn('bad.inc:2:5', message)
        self.assertIn('Undefined symbol', message)
        self.assertEqual(m.word(0xc401), 2)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf90]), bytes(16))
        self.include_file('ERRORS/loop.inc', '.include "./LOOP.INC"\n')
        self.assert_error('.org $300\n.include "ERRORS/loop.inc"', 'Recursive include', 2)
        self.assert_error('.org $300\n.include "ABSENT.INC"', 'Include file not found', 2)
        self.assert_error('.org $300\n.include ""', 'Invalid', 2)
        self.assert_error('.org $300\n.include "../outside.inc"', 'Invalid', 2)
        self.assert_error('.org $300\n.include "unterminated', 'Syntax', 2)
        self.include_file('TRAIL.INC', '.byte 1')
        self.assert_error('.org $300\n.include "TRAIL.INC" garbage', 'Syntax', 2)

    def test_include_depth_and_file_limits(self):
        for i in range(5):
            self.include_file(f'DEPTH/F{i}.INC', f'.include "F{i+1}.INC"' if i<4 else '.byte 1')
        self.assert_error('.org $300\n.include "DEPTH/F0.INC"', 'nested too deeply', 2)
        self.include_file('BIG.INC', b';' + b' '*16384)
        self.assert_error('.org $300\n.include "BIG.INC"', 'exceeds 16384', 2)
        self.include_file('EMPTY.INC', '')
        self.assert_code('.org $300\n.include "EMPTY.INC"\nnop', 'ea')
        self.assert_error('.org $300\n'+'.include "EMPTY.INC"\n'*17+'nop', 'Too many includes', 18)

    def test_include_repetition_four_levels_and_end(self):
        self.include_file('REPEAT.INC', '.byte 7')
        self.assert_code('.org $300\n.include "REPEAT.INC"\n.include "REPEAT.INC"\nrts', '07 07 60')
        for i in range(4):
            self.include_file(f'FOUR/F{i}.INC', f'.include "F{i+1}.INC"\n.byte {i}' if i<3 else '.byte 3')
        self.assert_code('.org $300\n.include "FOUR/F0.INC"\nrts', '03 02 01 00 60')
        self.include_file('STOP.INC', '.byte 42\n.end\ninvalid')
        self.assert_code('.org $300\n.include "STOP.INC"\ninvalid', '2a')

    def test_include_cache_address_crossing_and_capacity(self):
        # An allocated image at $80-$8C makes cache addresses cross $90000.
        body = b'.byte 42\n' + (b';' + b' '*249+b'\n')*20
        self.include_file('CROSS.INC', body)
        m = Machine()
        m.bus.m[0xcf80:0xcf8d] = bytes([0x20])*13
        status, message, output = m.assemble('.org $300\n'+'.include "CROSS.INC"\n'*3)
        self.assertEqual(status, 0, message)
        self.assertEqual(output, bytes([42])*3)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf8d]), bytes([0x20])*13)
        self.assertEqual(bytes(m.bus.m[0xcf8d:0xcf9d]), bytes(16))
        body = (b';'+b' '*252+b'\n')*64 + b';'+b' '*127
        self.assertEqual(len(body), 16384)
        self.include_file('CAPACITY.INC', body)
        m = Machine()
        status, message, _ = m.assemble('.org $300\n'+'.include "CAPACITY.INC"\n'*4,
                                        max_steps=20000000)
        self.assertEqual(status, 1)
        self.assertIn('cache exceeds 65535', message)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf90]), bytes(16))

    def test_editor_include_error_preserves_source_and_image(self):
        self.include_file('UIBAD.INC', '; comment\nlda missing')
        m = Machine()
        source = '.org $0300\n.include "UIBAD.INC"\nrts\n'
        m.editor(source+'\x01', pause=True)
        row = ''.join(chr(c) for c in m.bus.g[24])
        self.assertIn('Line 2', row)
        self.assertIn('UIBAD.INC:2:5', row)
        self.assertIn('Undefined symbol', row)
        self.assertEqual(m.word(0x16), 1)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf8d]), bytes([0x20])*13)
        self.assertEqual(bytes(m.bus.m[0xcf8d:0xcf9d]), bytes(16))
        self.assertEqual(bytes(m.bus.m[0x400:m.word(0x10)]) +
                         bytes(m.bus.m[m.word(0x12):0x4400]), source.replace('\n','\r').encode())

    def test_hardware_include_example(self):
        self.include_file('HWTEST/hardware.inc', (BUILD/'HARDWARE.INC').read_bytes()[2:])
        m = Machine()
        SIM['disk'].__globals__['CUR'][:] = ['HWTEST']
        status, message, native = m.assemble((ROOT/'asm/include-demo.asm').read_text())
        self.assertEqual(status, 0, message)
        self.assertEqual(native, bytes.fromhex('a9 41 8d 12 d0 a9 0d 8d 12 d0 60'))
        m.bus.m[0x300:0x300+len(native)] = native
        m.call(0x300)
        self.assertEqual(bytes(m.bus.out), b'A\r')

    def test_include_cache_is_snapshot_and_releases_memory(self):
        p = self.include_file('SNAP.INC', '.byte 42\n')
        env = SIM['Bus'].__setitem__.__globals__
        original = env['disk']
        loads = []
        def disk(bus, command):
            result = original(bus, command)
            if command == 3:
                loads.append(command)
                p.write_bytes(b'\x00\x04.byte 99\n')
            return result
        env['disk'] = disk
        try:
            self.assert_code('.org $300\n.include "SNAP.INC"', '2a')
        finally:
            env['disk'] = original
        self.assertEqual(loads, [3])
        m = Machine()
        m.bus.m[0xcf80:0xcfc0] = bytes([0x99])*64
        status, message, _ = m.assemble('.org $300\n.include "SNAP.INC"')
        self.assertEqual(status, 1)
        self.assertIn('No room for include cache', message)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcfc0]), bytes([0x99])*64)

    def assert_code(self, source, expected, gap=None):
        m = Machine()
        status, message, output = m.assemble(source, gap)
        self.assertEqual(status, 0, message)
        self.assertEqual(output, bytes.fromhex(expected))
        return m

    def assert_error(self, source, message, line=None):
        m = Machine()
        status, actual, _ = m.assemble(source)
        self.assertNotEqual(status, 0, actual)
        self.assertIn(message, actual)
        if line is not None:
            self.assertEqual(m.word(0xc401), line)

    def test_program_labels_and_gap(self):
        source = '.org $0300\nstart: lda #42\nsta $0400\nbne start\nrts\n'
        for gap in [0, 1, 15, len(source)]:
            self.assert_code(source, 'a9 2a 8d 00 04 d0 f9 60', gap)

    def test_directives_expressions_and_case(self):
        self.assert_code('base = $1234\n.org $0800\n.byte <base,>base,%1010,10,\'A\',"Hi"\n'
                         '.word base+2,*\n.res 3,$ff\n.org $0810\n.text "ok"\n.end\nINVALID',
                         '34 12 0a 0a 41 48 69 36 12 09 08 ff ff ff 00 00 6f 6b')

    def test_forward_and_zero_page_modes(self):
        self.assert_code('.org $0200\nlda target\nlda <target\nlda $10,x\nldx $10,y\n'
                         'lda ($10,x)\nlda ($11),y\njmp ($1234)\ntarget: rts',
                         'ad 10 02 a5 10 b5 10 b6 10 a1 10 b1 11 6c 34 12 60')

    def test_all_official_instructions(self):
        operands = {'imp':'','acc':' A','imm':' #$12','zpg':' $12','zpx':' $12,X',
                    'zpy':' $12,Y','abs':' $1234','abx':' $1234,X','aby':' $1234,Y',
                    'ind':' ($1234)','inx':' ($12,X)','iny':' ($12),Y','rel':' *+2'}
        for opcode, (name, mode) in enumerate(MPU.disassemble):
            if name == '???':
                continue
            with self.subTest(name=name, mode=mode):
                expected = [opcode] + ([] if mode in ('imp','acc') else
                                      [0] if mode == 'rel' else
                                      [0x34,0x12] if mode in ('abs','abx','aby','ind') else [0x12])
                self.assert_code('.org $0300\n' + name + operands[mode], bytes(expected).hex())

    def test_diagnostics(self):
        cases = [('lda #1','Set .ORG',1),('.org $300\nwat','Unknown',2),
                 ('.org $300\nlda absent','Undefined',2),
                 ('.org $300\nx: nop\nx: rts','Duplicate',3),
                 ('.org $300\nsta #1','addressing',2),
                 ('.org $300\nbne *+130','Branch out',2),
                 ('.org $300\n.byte 256','range',2),
                 ('.org $300\nlda ($1234,x)','range',2),
                 ('.org $300\n.res 16385','Output exceeds',2),
                 ('.org $300\n.org $200','backwards',2),
                 ('x = later\n.org $300\nlater: nop','Forward',1),
                 ('.org $300\nlda #1 garbage','Syntax',2),
                 ('.org $300\n.text "unfinished','Syntax',2),
                 ('.org $300\n.byte $10000','range',2),
                 ('.org $300','No bytes',None)]
        for source, msg, line in cases:
            with self.subTest(msg=msg, source=source):
                self.assert_error(source, msg, line)

    def test_fixed_binary_save_restores_source_and_core(self):
        for origin in [0x300, 0x500, 0x4400, 0x8400, 0xb000]:
            with self.subTest(origin=origin):
                m = self.assert_code(f'.org ${origin:04x}\nlda #42\nrts', 'a9 2a 60')
                # d_keep/d_load are patched by editor entry; emulate that ABI.
                labels = dict((s[2].lstrip('.'), int(s[1],16)) for ln in (BUILD/'asm.labels').read_text().splitlines() if len(s:=ln.split())==3)
                for label, offsets in [('d_keep',(4,5)),('d_load',(1,2))]:
                    for off,v in zip(offsets,[0,8]):
                        m.bus.banks[0x20000+labels[label]-0xe000+off] = v
                before = bytes(m.bus.m[:0xcc00])
                path = m.save(f'OUT{origin:04X}')
                self.assertEqual(path.read_bytes(), origin.to_bytes(2,'little')+bytes.fromhex('a9 2a 60'))
                # Save changes the prompt/result areas but must restore source,
                # generated bytes and executable core.
                self.assertEqual(m.bus.m[0x400:0xc400], before[0x400:0xc400])

    def test_banked_binary_save_keeps_application_bank(self):
        m = self.assert_code('.org $e000\nlda #42\nrts','a9 2a 60')
        editor = bytes(m.bus.banks[0x20000:0x21000])
        p = m.save('BANKBIN')
        self.assertEqual(p.read_bytes(), bytes.fromhex('00 e0 a9 2a 60'))
        self.assertEqual(m.bus.bank, 0x20)
        self.assertEqual(m.bus.banks[0x20000:0x21000], editor)

    def test_editor_assemble_save_exit_and_resume(self):
        m = Machine()
        caller = bytes(m.bus.m[0x300:0xcc00])
        source = '.org $0300\nlda #42\nsta $0400\nrts\n'
        m.editor(source+'\x01EDITORBIN\r\x1b')
        self.assertEqual(bytes(m.bus.m[0x300:0xcc00]), caller)
        p = Path(_disk.name)/'EDITORBIN'
        self.assertEqual(p.read_bytes(), bytes.fromhex('00 03 a9 2a 8d 00 04 60'))
        image = m.bus.banks[0x20000 + 0xf70]
        self.assertEqual(image, 0x80)
        self.assertEqual(bytes(m.bus.m[0xcf80:0xcf8d]), bytes([0x20])*13)
        # EDIT's independent workspace has not been touched.
        self.assertEqual(m.bus.banks[0xe0000:0xed000], bytes(0xd000))
        text = bytes(m.bus.banks[image*4096+0x400:image*4096+0x400+len(source)])
        self.assertEqual(text, source.replace('\n','\r').encode())
        m.editor('\x1b', entry=0xe003)
        self.assertEqual(m.bus.banks[0x20f70], image)
        self.assertEqual(bytes(m.bus.m[0x300:0xcc00]), caller)
        # The resulting program executes as a normal mini6502 disk binary.
        data = p.read_bytes()
        m.bus.m[0x300:0x300+len(data)-2] = data[2:]
        m.call(0x300)
        self.assertEqual(m.bus.m[0x400], 42)

    def test_editor_error_jumps_to_line(self):
        m = Machine()
        m.editor('.org $0300\nlda absent\nrts\n\x01', pause=True)
        self.assertEqual(m.word(0x16), 1)  # zero-based CURLINE
        row = ''.join(chr(c) for c in m.bus.g[24])
        self.assertIn('Line 2', row)
        self.assertIn('Undefined symbol', row)
        self.assertEqual(m.bus.cx, 4)

    def test_editor_refuses_binary_over_source(self):
        m = Machine()
        source = bytes.fromhex('00 04') + b'.org $0300\rlda #42\rrts\r'
        p = Path(_disk.name)/'SOURCE.ASM'
        p.write_bytes(source)
        name = b'SOURCE.ASM\0'
        m.bus.banks[0x20f80:0x20f80+len(name)] = name
        m.editor('\x01source.asm\r\x1b', entry=0xe006)
        self.assertEqual(p.read_bytes(), source)

    def test_editor_out_of_banks_returns_without_swapping(self):
        m = Machine()
        m.bus[0xd300] = 3
        m.bus[0xd508] = 3
        m.bus.m[0xcf80:0xcfc0] = bytes([0x99])*64
        before = bytes(m.bus.m[0x300:0xcc00])
        m.editor('')
        self.assertEqual(bytes(m.bus.m[0x300:0xcc00]), before)
        self.assertEqual(m.bus[0xd300], 3)
        self.assertEqual(m.bus[0xd508], 3)

    def test_desktop_file_launch_switches_display_and_restores_caller(self):
        for warm_reset in [False, True]:
            with self.subTest(warm_reset=warm_reset):
                m = Machine()
                source = '.org $0300\nlda #42\nrts\n'
                self.include_file('ASM/SCREEN.ASM', source)
                name = b'/ASM/SCREEN.ASM\0'
                m.bus.banks[0x20f80:0x20f80+len(name)] = name
                # Desktop's system-page handoff: LAUNCH calls TARGET through
                # the actual ROM FARCALL, returns to bank $14, then RESUME.
                m.bus.m[0xcca0:0xccab] = bytes.fromhex('20 b0 cc a9 14 8d 20 d0 4c 98 cc')
                m.bus.m[0xccb0:0xccb6] = bytes.fromhex('20 d0 ff 20 06 e0')
                m.bus.m[0xcc98:0xcc9e] = bytes.fromhex('a9 01 8d ff 02 60')
                m.bus.bank = 0x14
                m.bus[0xd300] = 3  # desktop hires screen remains active at launch
                m.bus[0xd508] = 3  # visible automatic graphics pointer
                m.bus.warm = 0xcc98
                m.bus.v.vram[:] = bytes([0xa5])*len(m.bus.v.vram)
                caller = bytes(m.bus.m[0x300:0xcc00])
                m.editor('', entry=0xcca0, pause=True)
                self.assertEqual(m.bus[0xd300], 0)
                self.assertEqual(m.bus[0xd508], 0)
                self.assertEqual(''.join(map(chr,m.bus.g[0])).rstrip(), '.org $0300')
                self.assertIn('Loaded', ''.join(map(chr,m.bus.g[24])))
                self.assertEqual(bytes(m.bus.v.vram), bytes([0xa5])*len(m.bus.v.vram))
                if warm_reset:
                    # F1 resets video and selects bank 0; G uses the saved stub.
                    m.bus[0xd000] = 3
                    m.bus.bank = 0
                    m.editor('\x1b', entry=m.bus.warm)
                else:
                    m.bus.queue = [27]
                    for _ in range(100000):
                        m.cpu.step()
                        if m.cpu.pc == 0x200:
                            break
                    self.assertEqual(m.cpu.pc, 0x200)
                self.assertEqual(m.bus[0xd300], 3)
                self.assertEqual(m.bus[0xd508], 3)
                self.assertEqual(m.bus.bank, 0x14)
                self.assertEqual(m.bus.warm, 0xcc98)
                self.assertEqual(m.bus.m[0x2ff], 1)  # desktop RESUME was reached
                self.assertEqual(bytes(m.bus.m[0x300:0xcc00]), caller)

    def test_monitor_entry_points_select_text_and_restore_display(self):
        for entry, mode in [(0xe000,1),(0xe003,4)]:
            with self.subTest(entry=entry, mode=mode):
                m = Machine()
                m.bus[0xd300] = mode
                m.bus[0xd508] = 1
                m.editor('', entry=entry, pause=True)
                self.assertEqual(m.bus[0xd300], 0)
                self.assertEqual(m.bus[0xd508], 0)
                m.bus.queue = [27]
                for _ in range(100000):
                    m.cpu.step()
                    if m.cpu.pc == 0x200:
                        break
                self.assertEqual(m.cpu.pc, 0x200)
                self.assertEqual(m.bus[0xd300], mode)
                self.assertEqual(m.bus[0xd508], 1)

    def test_editor_core_loads_from_app_folder_while_editing_elsewhere(self):
        m = Machine()
        docs = Path(_disk.name)/'DOCS'
        docs.mkdir(exist_ok=True)
        SIM['disk'].__globals__['CUR'][:] = ['DOCS']
        m.editor('.org $0300\nlda #42\nrts\n\x01FOLDERBIN\r\x1b')
        self.assertEqual((docs/'FOLDERBIN').read_bytes(), bytes.fromhex('00 03 a9 2a 60'))
        self.assertFalse((Path(_disk.name)/'ASMCORE').exists())
        self.assertEqual(SIM['disk'].__globals__['CUR'], ['DOCS'])

    def test_branch_limits_and_symbol_capacity(self):
        self.assert_code('.org $0300\nbne *-126\nbne *+129', 'd0 80 d0 7f')
        self.assert_error('.org $0300\nbne *-127', 'Branch out', 2)
        constants = ''.join(f's{i} = {i}\n' for i in range(256))
        self.assert_code(constants+'.org $0300\n.byte s255', 'ff')
        self.assert_error(constants+'extra = 1\n.org $0300\nnop', 'Symbol table full', 257)

    def test_disk_failure_preserves_working_memory(self):
        (Path(_disk.name)/'FAILOUT').mkdir(exist_ok=True)
        for origin in [0x8400, 0xe000]:
            with self.subTest(origin=origin):
                m = self.assert_code(f'.org ${origin:04x}\nnop', 'ea')
                for label, offsets in [('d_keep',(4,5)),('d_load',(1,2))]:
                    for off,v in zip(offsets,[0,8]):
                        m.bus.banks[0x20000+m.labels[label]-0xe000+off] = v
                before = bytes(m.bus.m[0x400:0xc400])
                m.save('FAILOUT')
                msg = bytes(m.bus.m[0xc500:0xc580]).split(b'\0')[0]
                self.assertIn(b'Disk error', msg)
                self.assertEqual(m.bus.m[0x400:0xc400], before)
                self.assertEqual(m.bus.bank, 0x20)

    def test_edit_binary_is_unchanged(self):
        obj = BUILD / 'edit-compat.o'
        out = BUILD / 'edit-compat.bin'
        subprocess.run(['ca65','-I',str(ROOT/'hw'),str(ROOT/'edit/edit.asm'),'-o',str(obj)], check=True)
        subprocess.run(['ld65','-C',str(ROOT/'edit/edit.cfg'),str(obj),'-o',str(out)], check=True)
        self.assertEqual(out.read_bytes(), (ROOT/'edit/edit.bin').read_bytes())

    def test_example_matches_ca65_and_executes(self):
        source = (ROOT/'asm/hello.asm').read_text()
        m = Machine()
        status, message, native = m.assemble(source)
        self.assertEqual(status, 0, message)
        config = BUILD/'hello.cfg'
        config.write_text('MEMORY { RAM: start = $0300, size = $1000, file = %O; }\n'
                          'SEGMENTS { CODE: load = RAM, type = rw; }\n')
        obj, out = BUILD/'hello.o', BUILD/'hello.bin'
        subprocess.run(['ca65',str(ROOT/'asm/hello.asm'),'-o',str(obj)], check=True)
        subprocess.run(['ld65','-C',str(config),str(obj),'-o',str(out)], check=True)
        self.assertEqual(native, out.read_bytes())
        m.bus.m[0x300:0x300+len(native)] = native
        m.call(0x300)
        self.assertIn(b'HELLO FROM ASM!', bytes(m.bus.out))


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]], verbosity=2)
