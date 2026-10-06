#include "timer.h"

uint32_t timer_read_mtime_l(void) {
    return TIMER_REG_MTIME_L;
}

uint32_t timer_read_mtime_h(void) {
    return TIMER_REG_MTIME_H;
}

uint64_t timer_read_mtime(void) {
    uint32_t high1, low, high2;
    do {
        high1 = TIMER_REG_MTIME_H;
        low   = TIMER_REG_MTIME_L;
        high2 = TIMER_REG_MTIME_H;
    } while (high1 != high2);
    return (((uint64_t)high2) << 32) | (uint64_t)low;
}

void timer_set_mtimecmp(uint64_t val) {
    TIMER_REG_MTIMECMP_H = 0xFFFFFFFFU;
    TIMER_REG_MTIMECMP_L = (uint32_t)(val & 0xFFFFFFFFU);
    TIMER_REG_MTIMECMP_H = (uint32_t)(val >> 32);
}

void delay_cycles(uint32_t cycles) {
    uint64_t start = timer_read_mtime();
    while ((timer_read_mtime() - start) < cycles) {
        /* Spin wait until requested cycles elapse */
    }
}
