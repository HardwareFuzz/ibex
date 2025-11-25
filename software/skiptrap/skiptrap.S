    .section .vectors,"ax",@progbits
    .align  4
    /* Simple System resets mtvec to the start of .vectors (0x0010_0000).
     * Place a trampoline here that jumps to the real trap handler in .text.
     * Pad to 0x80 bytes so .text starts at 0x0010_0080 as expected.
     */
    j       trap_handler
    .balign 128, 0

    .section .text
    .globl  _start

/* Minimal skip-on-trap test for RV32IMC (Ibex).
 * - Installs an mtvec trap handler that advances mepc by 2 or 4 bytes
 *   depending on the trapped instruction length (compressed or not).
 * - Executes a compressed breakpoint and a 32-bit illegal instruction
 *   to exercise both paths, then reports pass via tohost (0x20008) and spins.
 */
_start:
    /* mtvec already points to .vectors (0x0010_0000) in Simple System. */
    la      t0, trap_handler
    csrw    mtvec, t0
    /* Allow FP regs (if present): set mstatus.FS=Dirty and clear fcsr. */
    csrr    t0, mstatus
    li      t1, 0x00003000
    or      t0, t0, t1
    csrw    mstatus, t0
    csrw    fcsr, x0
    j       user_code

user_code:
    /* ------------------------------------------------------------ */
    /* X register writes (simple ALU)                               */
    /* ------------------------------------------------------------ */
    li      a0, 42
    addi    a1, a0, 5
    lui     a2, 0x12345
    add     a3, a1, a0
    xor     a4, a3, a2

    /* ------------------------------------------------------------ */
    /* Memory writes (I extension)                                  */
    /* ------------------------------------------------------------ */
    la      t2, mem_buf
    sw      a0, 0(t2)          /* aligned word store */
    sh      a1, 4(t2)          /* aligned half store */
    sb      a4, 6(t2)          /* byte store */

    /* ------------------------------------------------------------ */
    /* AMOs (A extension). If A not present, these trap & skip.     */
    /* ------------------------------------------------------------ */
    la      t3, amo_loc
    li      t4, 1
    amoadd.w t5, t4, (t3)      /* t5 <- old, mem <- old + 1 */
    amoswap.w t6, a0, (t3)     /* t6 <- old, mem <- a0 */

    /* ------------------------------------------------------------ */
    /* F register writes + memory (F extension). Without F -> trap. */
    /* ------------------------------------------------------------ */
    li      a5, 0x3f800000     /* 1.0f */
    fmv.w.x ft0, a5
    fsw     ft0, 8(t2)         /* mem_buf[8] = 1.0f */
    flw     ft1, 8(t2)
    fadd.s  ft2, ft1, ft0
    fsw     ft2, 12(t2)        /* mem_buf[12] = 2.0f (if F exists) */

    /* ------------------------------------------------------------ */
    /* Traps of different kinds                                     */
    /* ------------------------------------------------------------ */
    c.ebreak                    /* Breakpoint (cause=3) */
    ecall                       /* Env call from M-mode (cause=11) */
    .word   0xffffffff          /* Illegal instruction (cause=2) */
    /* Misaligned data access (cause=6 for store, 4 for load) */
    sw      a0, 1(t2)           /* misaligned store -> trap */
    lw      a7, 2(t2)           /* misaligned load  -> trap */
    /* Illegal CSR write to read-only CSR (cause=2) */
    csrw    mvendorid, x0
    /* SRET in M-mode (cause=2) */
    .insn   i 0x73, 0, x0, x0, 0x102 /* sret encoding */

    /* ------------------------------------------------------------ */
    /* Reached only if all traps skipped correctly                  */
    /* ------------------------------------------------------------ */
    addi    t0, x0, 1
    addi    t0, t0, 1

exit:
    /* Report success (1) via HTIF tohost then spin */
    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:
    j       1b

    .align  2
trap_handler:
    csrr    t0, mepc             /* faulting PC */
    csrr    t1, mcause           /* trap cause */
    csrr    t4, mtval

    /* If it's an interrupt (mcause[31]=1), guard against returning into the
     * second half of a 32-bit instruction (would cause endless re-trap).
     * If so, advance mepc by 2 to realign to the next instruction boundary.
     */
    bltz    t1, intr_path

    /* strip interrupt bit */
    slli    t5, t1, 1
    srli    t1, t5, 1

    /* default length assumes compressed (2 bytes) */
    li      t2, 2

    /* For these causes, mtval may hold the instruction encoding */
    li      t3, 2                /* illegal instruction */
    beq     t1, t3, use_mtval
    li      t3, 1                /* instruction access fault */
    beq     t1, t3, update_mepc
    li      t3, 12               /* instruction page fault */
    beq     t1, t3, update_mepc

    /* Otherwise, peek halfword at mepc to determine length */
    lhu     t4, 0(t0)
    j       decode_length

use_mtval:
    /* t4 already holds mtval */
    j       decode_length

decode_length:
    andi    t4, t4, 3
    li      t3, 3
    bne     t4, t3, compressed_len
    li      t2, 4                /* standard 32-bit instruction */
    j       update_mepc

compressed_len:
    li      t2, 2                /* compressed instruction */

update_mepc:
    add     t0, t0, t2           /* skip offending instruction */
    csrw    mepc, t0
    csrw    mcause, x0
    csrw    mtval, x0
    mret

/* Interrupt path: normally do not skip. But if mepc points at the second
 * halfword of a 32-bit instruction, bump by 2 to avoid livelock.
 */
intr_path:
    lhu     t4, 0(t0)            /* halfword at mepc */
    andi    t4, t4, 3
    li      t3, 3
    beq     t4, t3, intr_return  /* already at start of 32b insn */
    addi    t5, t0, -2
    lhu     t4, 0(t5)            /* check previous halfword */
    andi    t4, t4, 3
    li      t3, 3
    bne     t4, t3, intr_return  /* not in middle of a 32b insn */
    addi    t0, t0, 2            /* was middle of 32b insn -> step to end */
    csrw    mepc, t0
intr_return:
    csrw    mcause, x0
    csrw    mtval, x0
    mret
    /* No explicit tohost/fromhost symbols here; provided by linker script. */

    .section .data
    .align 4
amo_loc:
    .word 0x12345678

    .section .bss
    .align 4
mem_buf:
    .space 16
