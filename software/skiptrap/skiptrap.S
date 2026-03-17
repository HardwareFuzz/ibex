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
 * - Executes traps of different kinds, then reports pass via tohost and spins.
 */
_start:
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
    li      a0, 42
    addi    a1, a0, 5
    lui     a2, 0x12345
    add     a3, a1, a0
    xor     a4, a3, a2

    la      t2, mem_buf
    sw      a0, 0(t2)
    sh      a1, 4(t2)
    sb      a4, 6(t2)

    /* AMOs (A extension). If A not present, these trap & skip. */
    la      t3, amo_loc
    li      t4, 1
    amoadd.w t5, t4, (t3)
    amoswap.w t6, a0, (t3)

    /* F extension. If F not present, these trap & skip. */
    li      a5, 0x3f800000
    fmv.w.x ft0, a5
    fsw     ft0, 8(t2)
    flw     ft1, 8(t2)
    fadd.s  ft2, ft1, ft0
    fsw     ft2, 12(t2)

    c.ebreak
    ecall
    .word   0xffffffff
    sw      a0, 1(t2)
    lw      a7, 2(t2)
    csrw    mvendorid, x0
    .insn   i 0x73, 0, x0, x0, 0x102 /* sret */

exit:
    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:
    j       1b

    .align  2
trap_handler:
    csrr    t0, mepc
    csrr    t1, mcause
    csrr    t4, mtval

    bltz    t1, intr_path

    slli    t5, t1, 1
    srli    t1, t5, 1

    li      t2, 2

    li      t3, 2
    beq     t1, t3, use_mtval

    lhu     t4, 0(t0)
    j       decode_length

use_mtval:
    j       decode_length

decode_length:
    andi    t4, t4, 3
    li      t3, 3
    bne     t4, t3, compressed_len
    li      t2, 4
    j       update_mepc

compressed_len:
    li      t2, 2

update_mepc:
    add     t0, t0, t2
    csrw    mepc, t0
    csrw    mcause, x0
    csrw    mtval, x0
    mret

intr_path:
    lhu     t4, 0(t0)
    andi    t4, t4, 3
    li      t3, 3
    beq     t4, t3, intr_return
    addi    t5, t0, -2
    lhu     t4, 0(t5)
    andi    t4, t4, 3
    li      t3, 3
    bne     t4, t3, intr_return
    addi    t0, t0, 2
    csrw    mepc, t0
intr_return:
    csrw    mcause, x0
    csrw    mtval, x0
    mret

    .section .data
    .align 4
amo_loc:
    .word 0x12345678

    .section .bss
    .align 4
mem_buf:
    .space 16
