#include "uart.h"

int uart_tx_ready(void) {
    return (UART_REG_STATUS & UART_STATUS_TX_READY) != 0;
}

void uart_putc(char c) {
    while (!uart_tx_ready()) {
        /* Spin wait for transmit ready */
    }
    UART_REG_TXDATA = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s) {
    if (!s) return;
    while (*s) {
        uart_putc(*s++);
    }
}

char uart_getc(void) {
    while (!(UART_REG_STATUS & UART_STATUS_RX_VALID)) {
        /* Spin wait for receive byte */
    }
    return (char)(UART_REG_RXDATA & 0xFF);
}

void uart_puthex(uint32_t val) {
    static const char hex_digits[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--) {
        uart_putc(hex_digits[(val >> (i * 4)) & 0xF]);
    }
}
