#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

#define TIMER_BASE              0x20000010U
#define TIMER_REG_MTIME_L       (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_REG_MTIME_H       (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_REG_MTIMECMP_L    (*(volatile uint32_t *)(TIMER_BASE + 0x08))
#define TIMER_REG_MTIMECMP_H    (*(volatile uint32_t *)(TIMER_BASE + 0x0C))

uint64_t timer_read_mtime(void);
uint32_t timer_read_mtime_l(void);
uint32_t timer_read_mtime_h(void);
void     timer_set_mtimecmp(uint64_t val);
void     delay_cycles(uint32_t cycles);

#endif /* TIMER_H */
