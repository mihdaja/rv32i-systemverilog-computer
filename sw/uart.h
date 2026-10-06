#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_BASE             0x20000000U
#define UART_REG_TXDATA       (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_REG_STATUS       (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_REG_RXDATA       (*(volatile uint32_t *)(UART_BASE + 0x08))

#define UART_STATUS_TX_READY  0x00000001U
#define UART_STATUS_RX_VALID  0x00000002U

int  uart_tx_ready(void);
void uart_putc(char c);
void uart_puts(const char *s);
char uart_getc(void);
void uart_puthex(uint32_t val);

#endif /* UART_H */
