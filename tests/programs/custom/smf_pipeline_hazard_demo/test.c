/*
 * smf_pipeline_hazard_demo.c
 *
 * Demonstrates the cv32e40p mstatus.FS pipeline RAW hazard that causes SmF-00
 * to fail in ACT4 certification.
 *
 * Three tests:
 *   Test 1 (no NOP): reads FS=Initial (01) — the pipeline hazard
 *   Test 2 (1 NOP):  reads FS=Dirty   (11) — correct after 1 cycle delay
 *   Test 3 (fadd.s): reads FS=Dirty   (11) — APU ops write back one stage earlier
 *
 * PASS (writes 123456789 to 0x20000000) if all three match expectations.
 * FAIL (writes 1         to 0x20000000) if any check is wrong.
 */

#include <stdint.h>

#define TESTSTATUS  ((volatile uint32_t *)0x20000000)
#define TEST_PASS   123456789u
#define TEST_FAIL   1u

#define FS_MASK     0x00006000u   /* mstatus bits 14:13 */
#define FS_INITIAL  0x00002000u   /* FS = 01 */
#define FS_DIRTY    0x00006000u   /* FS = 11 */

/* Memory location used as the source for flw. Value does not matter. */
volatile float fp_scratch = 1.5f;

int main(void)
{
    uint32_t mstatus_no_nop;
    uint32_t mstatus_one_nop;
    uint32_t mstatus_fadd;

    /* ------------------------------------------------------------------
     * Test 1: flw immediately followed by csrrs mstatus
     * ------------------------------------------------------------------ */
    asm volatile (
        "lui   t1, 6               \n\t"  /* t1 = 0x6000 (FS field mask) */
        "csrc  mstatus, t1         \n\t"  /* clear bits 14:13 FS=00 (Off) */
        "lui   t1, 2               \n\t"  /* t1 = 0x2000 (FS=Initial) */
        "csrs  mstatus, t1         \n\t"  /* set  bit  13 FS=01 (Initial) */
        /* ---- hazard sequence: zero NOPs ---- */
        "flw   f0, 0(%1)           \n\t"  /* FP load: fregs_we fires in WB */
        "csrrs %0, mstatus, x0     \n\t"  /* CSR read in EX, same cycle as WB above */
        : "=r" (mstatus_no_nop)
        : "r"  (&fp_scratch)
        : "t1", "f0", "memory"
    );

    /* ------------------------------------------------------------------
     * Test 2: flw with exactly ONE nop before csrrs mstatus
     * ------------------------------------------------------------------ */
    asm volatile (
        "lui   t1, 6               \n\t"
        "csrc  mstatus, t1         \n\t"
        "lui   t1, 2               \n\t"
        "csrs  mstatus, t1         \n\t"
        /* ---- 1 NOP between flw and csrrs ---- */
        "flw   f0, 0(%1)           \n\t"  /* fregs_we fires in WB at cycle T */
        "nop                       \n\t"  /* mstatus_fs_q latches Dirty at T+1 */
        "csrrs %0, mstatus, x0     \n\t"  /* EX at T+1 reads Dirty */
        : "=r" (mstatus_one_nop)
        : "r"  (&fp_scratch)
        : "t1", "f0", "memory"
    );

    /* ------------------------------------------------------------------
     * Test 3: fadd.s (APU single-cycle) immediately followed by csrrs
     * ------------------------------------------------------------------ */
    asm volatile (
        "lui   t1, 6               \n\t"
        "csrc  mstatus, t1         \n\t"
        "lui   t1, 2               \n\t"
        "csrs  mstatus, t1         \n\t"
        /* ---- APU: fregs_we fires in EX, not WB ---- */
        "fadd.s f0, f1, f2         \n\t"  /* fregs_we via regfile_alu_we_fw (EX) */
        "csrrs  %0, mstatus, x0    \n\t"  /* EX one cycle later reads Dirty */
        : "=r" (mstatus_fadd)
        :
        : "t1", "f0", "f1", "f2"
    );

    /*
     * Verify all three observations match expectations:
     *   - no_nop sees Initial  (pipeline hazard confirmed)
     *   - one_nop sees Dirty   (1-cycle delay confirmed)
     *   - fadd    sees Dirty   (APU path correct)
     */
    int pass = ((mstatus_no_nop  & FS_MASK) == FS_INITIAL) &&
               ((mstatus_one_nop & FS_MASK) == FS_DIRTY)   &&
               ((mstatus_fadd    & FS_MASK) == FS_DIRTY);

    *TESTSTATUS = pass ? TEST_PASS : TEST_FAIL;

    return 0;
}
