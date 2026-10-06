#include "uart.h"

int main(void) {
    uart_puts("Hello, RV32I SystemVerilog Computer!\n");
    return 0; /* crt0 handles writing 1 to SIM_EXIT_ADDR on exit */
}
