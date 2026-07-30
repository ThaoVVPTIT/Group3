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

int main(void) {
  uart_init();

  uart_puts("\r\n=== HUNG ===\r\n");

  char buffer[100];
  int len = 0;
  uint32_t idle_counter = 0;
  int is_new_string = 0;

  while (1) {
    int32_t c = UART_DATA;
    if (c >= 0) {
      char ch = (char)(c & 0xFF);
      if (len < 99) {
        buffer[len++] = ch; // Lưu ký tự vào bộ đệm (không echo ngay để tránh stall CPU)
      }
      is_new_string = 1; // Đang nhận chuỗi
      idle_counter = 0;  // Reset bộ đếm thời gian im lặng
    } else {
      if (is_new_string) {
        idle_counter++;
        // Chờ khoảng 20-30ms im lặng (không có dữ liệu mới)
        if (idle_counter >= 100000) {
          buffer[len] = '\0'; // Đóng gói chuỗi
          
          // Xuống dòng trước
          uart_putchar('\r');
          uart_putchar('\n');
          
          // In ra toàn bộ chuỗi đã nhận
          uart_puts(buffer);
          
          len = 0;           // Reset bộ đệm
          is_new_string = 0; // Reset trạng thái
          idle_counter = 0;
        }
      }
    }
  }

  return 0;
}
