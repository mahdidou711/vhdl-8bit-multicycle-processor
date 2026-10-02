# 8-bit Multicycle Processor in VHDL

[![GHDL verification](https://github.com/mahdidou711/vhdl-8bit-multicycle-processor/actions/workflows/ghdl.yml/badge.svg)](https://github.com/mahdidou711/vhdl-8bit-multicycle-processor/actions/workflows/ghdl.yml)

> **Quick overview** — VHDL · processor architecture · verification & DE1 port preparation · exhaustive GHDL ALU verification · **1,573,888** ALU/sub-unit vectors · GitHub Actions CI

A minimal 8-bit multicycle processor with a fixed internal program ROM,
extending an existing university RTL design. It is checked by a self-checking
GHDL test suite (1,573,888 exhaustive vectors across the ALU and sub-units,
plus an 8-testbench edge-by-edge regression) and prepared for a Terasic DE1
(Cyclone II) FPGA port. The repository includes the board wrapper and Quartus
project files prepared for the DE1 target.

## Key features

- Multicycle control FSM: `FETCH`, `DECODE`, `LOAD_IMM`, `WAIT_UAL`, `CAPTURE`,
  `WRITEBACK`, `HALT`.
- Fixed 16 x 8 instruction ROM, program counter PC (0..15), instruction
  register, operand registers A and B, result register R, flags Z/N/C/V.
- Registered 12-operation ALU with a `start`/`done` handshake: add/subtract,
  logic, shifts and rotation, plus a sequential 8 x 8 shift-add multiplier and
  a sequential 16-bit integer square root.
- Exhaustive verification of every ALU sub-unit and of the complete ALU
  (all 16 opcodes x all 8-bit A x all 8-bit B).
- Processor testbench that checks R and the flags against a reference model on
  every rising clock edge, including the HALT boundary and asynchronous reset
  in the middle of an operation.
- DE1 wrapper that leaves the processor RTL unchanged: demonstration clock
  divider, reset synchronizer, LED and hexadecimal display outputs.
- GitHub Actions workflow running the regression and the FPGA GHDL checks.

## Architecture

```text
                        fixed ROM, 16 x 8
                               |
                               | ROM[PC]
                               v
   +---------+           +-----------+           +-------------------------+
   |   PC    |---------->|    IR     |---------->|      control FSM        |
   |  0..15  |           +-----------+           | FETCH  DECODE  LOAD_IMM |
   +---------+                                   | WAIT_UAL  CAPTURE       |
                                                 | WRITEBACK  HALT         |
                                                 +-------------------------+
                                                   | load A/B   | start, OP  ^ done
                      immediate byte ROM[PC]       v            v            |
                     ---------------------->  +---------+   +---------+      |
                                              |  A, B   |-->|  ual_8  |------+
                                              +---------+   +---------+
                                                                 | RESULT, Z/N/C/V
                                                                 v
                                                          +-------------+
                                                          | R, Z/N/C/V  |---> outputs
                                                          +-------------+
```

A and B are loaded only from immediate bytes in the ROM. R is written only by
ALU operations and is never fed back into the datapath. The design has no data
memory, register file, branches, stack or external instruction memory.

### Module hierarchy

| Module | File | Type | Role |
| --- | --- | --- | --- |
| `proc_8` | `rtl/proc_8.vhd` | sequential | ROM, PC, IR, A/B/R, flags, control FSM |
| `ual_8` | `rtl/ual_8.vhd` | sequential | ALU: operation select, output registers, `start`/`done` FSM |
| `addsub_8` | `rtl/addsub_8.vhd` | combinational | 8-bit ripple-carry adder/subtractor (ADD, SUB) |
| `logic_8` | `rtl/logic_8.vhd` | combinational | AND, OR, XOR, NOT A |
| `shifter_8` | `rtl/shifter_8.vhd` | combinational | SHL, SHR, SAR, ROL with shifted-out bit |
| `mult_shift_add` | `rtl/mult_shift_add.vhd` | sequential | unsigned 8 x 8 -> 16 shift-add multiplier, 8 iterations |
| `sqrt16` | `rtl/sqrt16.vhd` | sequential | integer square root of a 16-bit input, 8 iterations |

All sequential modules use an asynchronous active-low reset. Source comments
in `rtl/` are in French.

### Instruction timing

The control FSM executes one state per rising clock edge. In the table below,
**edge 1** is the rising edge on which the FSM executes `FETCH` for the
instruction. Each count ends with the instruction's last state, inclusive, and
the next instruction's `FETCH` follows on the next edge.

| Instruction | FSM state on each rising edge | Edges | R and flags written on |
| --- | --- | ---: | --- |
| `LOAD_A` / `LOAD_B` | `FETCH`, `DECODE`, `LOAD_IMM` | 3 | not written (A or B loaded on edge 3) |
| Single-step ALU op (0-9, C-F) | `FETCH`, `DECODE`, 4 x `WAIT_UAL`, `CAPTURE`, `WRITEBACK` | 8 | edge 7 |
| `MUL` | `FETCH`, `DECODE`, 12 x `WAIT_UAL`, `CAPTURE`, `WRITEBACK` | 16 | edge 15 |
| `SQRT` | `FETCH`, `DECODE`, 13 x `WAIT_UAL`, `CAPTURE`, `WRITEBACK` | 17 | edge 16 |
| `HALT` | `FETCH`, `DECODE`, then `HALT` on every later edge | - | never |

Each instruction spends one more edge in `WAIT_UAL` than the ALU latency of the
operation. That latency is 3, 11 or 12 edges, counted from the edge on which
`ual_8` accepts `start` to the edge on which it raises `done`. The FSM observes
`done` one edge later. These figures are derived from `rtl/proc_8.vhd` and
`rtl/ual_8.vhd`. The processor testbench checks R and the flags on every
rising edge against a model that uses the same edge accounting.

## Instruction set

| Byte | Instruction | Behavior |
| --- | --- | --- |
| `0x10` | `LOAD_A` | A <- next ROM byte; PC skips the immediate |
| `0x11` | `LOAD_B` | B <- next ROM byte; PC skips the immediate |
| `0xFF` | `HALT` | FSM enters `HALT`; outputs hold their values |
| any other byte | ALU operation | low nibble selects the ALU opcode; the high nibble is ignored |

Both PC increments, in `FETCH` and in `LOAD_IMM`, are explicitly modulo 16.

### ALU operations

For every operation, Z = 1 when the 8-bit result is `0x00` and N = result bit 7.

| Opcode | Mnemonic | Result | C | V |
| --- | --- | --- | --- | --- |
| `0` | `ADD` | (A + B) mod 256 | carry out (A + B > 255) | signed overflow |
| `1` | `SUB` | (A - B) mod 256 | borrow (A < B, unsigned) | signed overflow |
| `2` | `AND` | A and B | 0 | 0 |
| `3` | `OR` | A or B | 0 | 0 |
| `4` | `XOR` | A xor B | 0 | 0 |
| `5` | `NOT` | not A | 0 | 0 |
| `6` | `SHL` | logical shift left by 1 | A(7) | 0 |
| `7` | `SHR` | logical shift right by 1 | A(0) | 0 |
| `8` | `SAR` | arithmetic shift right by 1 | A(0) | 0 |
| `9` | `ROL` | rotate left by 1 | A(7) | 0 |
| `A` | `MUL` | low byte of the unsigned 16-bit product A x B | 0 | 0 |
| `B` | `SQRT` | floor(sqrt(`0x00` & A)) | 0 | 0 |
| `C`-`F` | unused | `0x00` (so Z = 1) | 0 | 0 |

Notes on the flag semantics:

- **SUB:** C is a borrow at the ALU level. The internal `addsub_8` unit outputs
  the raw adder carry (1 = no borrow), and `ual_8` inverts it.
- **MUL:** the high byte of the product is discarded and C/V are cleared, even
  when the product does not fit in 8 bits.
- **Unary operations** (NOT, shifts, ROL, SQRT) and opcodes C-F ignore B.
- **Reset** clears R and all four flags. Z therefore reads 0 after reset even
  though R = `0x00`, because Z is updated only by an ALU operation.

## Fixed ROM program

The ROM loads A = `0x19` (25) and B = `0x07` (7), then applies every ALU
operation except NOT and the unused opcodes:

| Addr | Byte(s) | Instruction | R | Z N C V |
| --- | --- | --- | --- | --- |
| 0-1 | `10 19` | `LOAD_A 0x19` | | |
| 2-3 | `11 07` | `LOAD_B 0x07` | | |
| 4 | `00` | `ADD` | `0x20` | 0 0 0 0 |
| 5 | `01` | `SUB` | `0x12` | 0 0 0 0 |
| 6 | `02` | `AND` | `0x01` | 0 0 0 0 |
| 7 | `03` | `OR` | `0x1F` | 0 0 0 0 |
| 8 | `04` | `XOR` | `0x1E` | 0 0 0 0 |
| 9 | `06` | `SHL` | `0x32` | 0 0 0 0 |
| 10 | `07` | `SHR` | `0x0C` | 0 0 1 0 |
| 11 | `08` | `SAR` | `0x0C` | 0 0 1 0 |
| 12 | `09` | `ROL` | `0x32` | 0 0 0 0 |
| 13 | `0A` | `MUL` | `0xAF` | 0 1 0 0 |
| 14 | `0B` | `SQRT` | `0x05` | 0 0 0 0 |
| 15 | `FF` | `HALT` | `0x05` held | 0 0 0 0 held |

Rising edges are counted from reset release, and edge 1 is the `FETCH` of
ROM[0]. The final result, `0x05`, is written on edge 110, and the processor
testbench checks this. The processor then fetches `0xFF` from ROM[15] and
remains in `HALT` with stable outputs.

## Verification

All tests are self-checking VHDL testbenches run with GHDL. Each testbench
prints a `TB_RESULT <name> PASS|FAIL` line, which `sim/ghdl/run_tests.sh`
combines with the simulator exit status.

| Test | Unit under test | Stimulus | Vectors | Directed checks |
| --- | --- | --- | ---: | ---: |
| `addsub_8` | `addsub_8` | exhaustive: mode x A x B | 131,072 | 0 |
| `logic_8` | `logic_8` | exhaustive: OP x A x B | 262,144 | 0 |
| `shifter_8` | `shifter_8` | exhaustive: OP x A | 1,024 | 0 |
| `mult_shift_add` | `mult_shift_add` | exhaustive: A x B | 65,536 | 7 |
| `sqrt16` | `sqrt16` | exhaustive: every 16-bit input | 65,536 | 7 |
| `ual_8` | `ual_8` | exhaustive: 16 opcodes x A x B | 1,048,576 | 12 |
| `proc_8_program` | `proc_8` | fixed program, reset during an ALU operation, full rerun | 15 result captures | 161 clock edges |
| `proc_8_halt` | `proc_8` | full program, HALT at ROM[15], 200 edges in HALT | 11 result captures | 318 clock edges |

Current result: **8 PASS, 0 FAIL**. The six exhaustive testbenches apply
**1,573,888** vectors with **0 errors**.

### What is checked

- **Independent reference model.** `tb/tb_pkg.vhd` computes expected values
  with integer arithmetic rather than the ripple-carry and bit-slice structure
  of the RTL. Square roots are checked with the property
  r * r <= X < (r + 1) * (r + 1).
- **Exact latency.** Edge 1 is the edge that accepts `start`. `done` must stay
  low until the expected edge and be high on it: edge 9 for `mult_shift_add`,
  edge 10 for `sqrt16`, and edges 3, 11 and 12 for single-step operations, MUL
  and SQRT in `ual_8`. RESULT and the flags must not change before the last
  two edges of an ALU operation.
- **Handshake behavior.** `start` is held for 0, 1 or 2 edges after `done`
  rises, or pulsed for a single edge on the multiplier and square root. The
  multiplier and square-root tests change the inputs after the capture edge to
  confirm the captured copy is used.
- **Asynchronous reset** during multiplication, square root, an ALU MUL and a
  processor ALU instruction, followed by recovery.
- **Processor, edge by edge.** R, Z, N, C and V are compared with an
  instruction-level model on every rising edge. The model's results are also
  cross-checked against a hand-derived trace of the program.
- **HALT boundary.** The fetch of ROM[15] at PC = 15, entry into `HALT`, and
  200 further edges with frozen outputs. This is longer than a full program
  pass, so an unwanted restart would be detected.

### Program counter note

`PC` is declared with range 0..15. In the imported RTL, both increments were a
plain `PC + 1`, and fetching ROM[15] took PC out of range, stopping the GHDL
simulation before `HALT` was decoded. Both increments, in `FETCH` and in
`LOAD_IMM`, now use explicit modulo-16 arithmetic. The regression covers the
fetch of ROM[15] and entry into `HALT`.

## FPGA port preparation: Terasic DE1

| Item | Value |
| --- | --- |
| Board | Terasic DE1 |
| FPGA | Altera Cyclone II `EP2C20F484C7` |
| Top level | `proc8_de1_top` (`fpga/de1/proc8_de1_top.vhd`) |
| Quartus files | `proc8_de1.qpf`, `proc8_de1.qsf`, `proc8_de1.sdc` |

### Board interface

| Board signal | Function |
| --- | --- |
| `CLOCK_50` | 50 MHz board clock |
| `KEY0` | active-low reset |
| `LEDR[7:0]` | result register R |
| `LEDG0` | Z |
| `LEDG1` | N |
| `LEDG2` | C |
| `LEDG3` | V |
| `HEX0` | low nibble of R, hexadecimal |
| `HEX1` | high nibble of R, hexadecimal |

### Wrapper

The wrapper instantiates `proc_8` without modification and adds only board
glue:

- **Demonstration clock.** `proc_8` has no clock-enable input. At 50 MHz, the
  110 edges up to the final result would last 2.2 µs. The wrapper therefore
  toggles a register every `CORE_CLK_HALF_PERIOD` = 3,125,000 cycles of
  `CLOCK_50`, giving an 8 Hz core clock. With this divider setting, the final
  result appears roughly 14 seconds after reset release. The divisor is a
  generic.
- **Reset synchronizer.** `KEY0` passes through two registers: reset asserts
  asynchronously and deasserts synchronously to `CLOCK_50`. The core clock is
  held low during reset.
- **Seven-segment decoding.** Hexadecimal digits 0-F for the active-low DE1
  displays.

The Quartus settings select VHDL-1993 and reserve all unused pins as
tri-stated inputs. The SDC file declares a 20 ns constraint on `CLOCK_50`, a
divide-by-6,250,000 generated clock for the core clock register, and a false
path from the asynchronous `KEY0` input. Each of the 28 wrapper port bits has
exactly one location assignment, with no duplicate pins. The pin mapping and
board interface correspond to the Terasic DE1 port preparation.

## Repository structure

```text
rtl/                 processor RTL: proc_8, ual_8 and the five ALU sub-units
tb/                  self-checking testbenches and shared reference package tb_pkg
sim/ghdl/            run_tests.sh (regression), check_fpga.sh (FPGA GHDL checks)
fpga/de1/            DE1 top-level wrapper, Quartus project, pins, SDC
.github/workflows/   ghdl.yml: CI for the regression and the FPGA checks
```

## Running the tests

Requirements: Bash and GHDL with synthesis support (`ghdl --synth`). The suite
was validated with GHDL 4.1.0.

```bash
./sim/ghdl/run_tests.sh
```

Expected output (per-test run times omitted):

```text
[PASS ] addsub_8          vectors=131072 directed=0 errors=0
[PASS ] logic_8           vectors=262144 directed=0 errors=0
[PASS ] shifter_8         vectors=1024 directed=0 errors=0
[PASS ] mult_shift_add    vectors=65536 directed=7 errors=0
[PASS ] sqrt16            vectors=65536 directed=7 errors=0
[PASS ] ual_8             vectors=1048576 directed=12 errors=0
[PASS ] proc_8_program    vectors=15 directed=161 errors=0
[PASS ] proc_8_halt       vectors=11 directed=318 errors=0

Summary: 8 passed, 0 failed
RESULT: OK
```

For the processor tests, `vectors` counts verified result captures and
`directed` counts compared clock edges.

To run a subset, pass test names:

```bash
./sim/ghdl/run_tests.sh ual_8 proc_8_halt
```

`KEEP_WORK=1` keeps the temporary build and log directory, and `GHDL` selects
the simulator binary:

```bash
KEEP_WORK=1 GHDL=/path/to/ghdl ./sim/ghdl/run_tests.sh
```

All build products are created in a temporary directory outside the
repository.

### Language flags

The script runs two analysis passes:

1. **Strict pass, `--std=93 -C`.** Every RTL and testbench file is analyzed as
   VHDL-93. `-C` is required only because a comment in `rtl/sqrt16.vhd`
   contains a UTF-8 `É`. Its second byte, 0x89, is a C1 control code, and
   strict VHDL-93 rejects it even inside comments.
2. **Simulation build, `--std=93 -frelaxed`.** `rtl/ual_8.vhd` and
   `rtl/proc_8.vhd` instantiate components without a configuration or `use`
   clause. Under strict VHDL-93 default binding, GHDL leaves these instances
   unbound. `-frelaxed` applies the VHDL-2002 default binding rule, which
   binds each one to the entity of the same name in `work`.

## FPGA verification & static checks

```bash
./sim/ghdl/check_fpga.sh
```

This script uses GHDL only. With `--std=93 -frelaxed`, it checks that:

- the seven RTL files and the DE1 wrapper analyze;
- `proc8_de1_top` elaborates;
- `ghdl --synth` accepts `proc8_de1_top`.

The CI workflow (`.github/workflows/ghdl.yml`) runs `run_tests.sh` and
`check_fpga.sh` in two jobs on push, pull request and manual dispatch, with
read-only repository permissions.

**Hardware status & coursework experience:** an earlier version of this design
ran on a physical Terasic DE1 board during university coursework (author
attestation only). That earlier version predates the modulo-16 program-counter
fix; the current fixed revision and the current public wrapper are prepared and
statically reviewed, but are not tested on physical board hardware. The
repository does not claim timing closure or a verified maximum clock
frequency (Fmax).

## Limitations

- **Fixed program.** The ROM is a constant in `rtl/proc_8.vhd`, so a different
  program requires editing the RTL.
- **Minimal instruction set.** The only instructions are LOAD_A, LOAD_B, HALT
  and single ALU operations on A and B. There are no branches, data memory,
  register file or stack, and R cannot be used as an operand.
- **Silent MUL truncation.** The high byte of the product is discarded without
  setting C or V.
- **Generated core clock.** The 8 Hz clock is a register output, not a PLL
  output or a clock enable. The current repository does not include a timing
  report for this generated clock, so no timing-margin or Fmax claim is made.

## Provenance

This repository extends and adapts an existing RTL design from university
coursework on processor architecture; the complete processor was not built from
scratch. The processor's control FSM, ALU, and datapath architecture originate
from the coursework design. Mehdi Bouama contributed the verification
environment (all eight GHDL testbenches and the independent reference model in
`tb/tb_pkg.vhd`), the program-counter modulo-16 boundary fix, the Terasic DE1
port preparation, continuous integration, and documentation. Exclusive
authorship of the original coursework RTL is not claimed.

No license is currently provided for this repository.
