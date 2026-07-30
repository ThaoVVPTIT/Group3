#include <stdint.h>

#define UART_DATA (*(volatile int32_t *)0x02000008)
#define UART_DIV (*(volatile uint32_t *)0x02000004)

void delay_ms(uint32_t ms) {
  uint32_t count = ms * 4150;
  while (count--) {
    __asm__ volatile("" : : : "memory");
  }
}

void uart_init(void) {
  UART_DIV = 434; // 115200 baud ở tần số 50MHz
}

void uart_putchar(char c) {
  if (c == '\n') {
    UART_DATA = '\r';
  }
  UART_DATA = c;
}

void uart_puts(const char *s) {
  while (*s) {
    uart_putchar(*s++);
  }
}

int32_t uart_getchar(void) {
  int32_t val = UART_DATA;
  if (val == -1) {
    return -1;
  }
  return val & 0xFF;
}

int main(void) {
  uart_init();

  uart_puts("\r\n=== PICORV32 UART ECHO TEST ===\r\n");

  while (1) {
    int32_t c = UART_DATA;
    if (c >= 0) {
      uart_putchar((char)(c & 0xFF));
    }
  }

  return 0;
}
