#include <stdint.h>

// Địa chỉ các thanh ghi ngoại vi
#define LED_REG      (*(volatile uint32_t *)0x03000000)
#define UART_DATA    (*(volatile int32_t  *)0x02000008)
#define UART_DIV     (*(volatile uint32_t *)0x02000004)

// Hàm delay đếm thuần thanh ghi
void delay_ms(uint32_t ms) {
    uint32_t count = ms * 8300;
    while (count--) {
        __asm__ volatile ("" : : : "memory");
    }
}

// Khởi tạo UART với Baudrate mong muốn (tần số CLK mặc định là 50MHz)
void uart_init(uint32_t baud) {
    // Công thức tính bộ chia: DIV = CLK_FREQ / BAUD
    // Với CLK_FREQ = 50.000.000 Hz, Baudrate = 115200 -> DIV = 434
    UART_DIV = 50000000 / baud;
}

// Gửi 1 ký tự qua UART (Stall phần cứng tự động nếu UART đang bận)
void uart_putchar(char c) {
    if (c == '\n') {
        UART_DATA = '\r';
    }
    UART_DATA = c;
}

// Gửi chuỗi ký tự qua UART
void uart_puts(const char *s) {
    while (*s) {
        uart_putchar(*s++);
    }
}

// Nhận 1 ký tự qua UART (Không chặn - Non-blocking)
// Trả về -1 nếu không có ký tự nào trong buffer nhận
int uart_getchar_nonblocking(void) {
    int32_t val = UART_DATA;
    if (val == -1) {
        return -1; // Buffer nhận rỗng
    }
    return val & 0xFF;
}

// Nhận 1 ký tự qua UART (Chặn - Blocking)
char uart_getchar(void) {
    int val;
    while ((val = uart_getchar_nonblocking()) == -1) {
        // Chờ đến khi nhận được dữ liệu
    }
    return (char)val;
}

int main(void) {
    // Khởi tạo UART ở tốc độ 115200 baud
    uart_init(115200);
    
    // Đèn LED nháy kiểm tra phần cứng
    LED_REG = 0x55;
    delay_ms(300);
    LED_REG = 0xAA;
    delay_ms(300);
    LED_REG = 0x00;
    
    // In lời chào ra màn hình Terminal máy tính
    uart_puts("\r\n");
    uart_puts("==================================================\r\n");
    uart_puts("  PicoRV32 RISC-V CPU - DE10-Lite FPGA UART Test  \r\n");
    uart_puts("==================================================\r\n");
    uart_puts("Baudrate: 115200 | CPU CLK: 50 MHz\r\n\r\n");
    uart_puts("Huong dan test:\r\n");
    uart_puts("1. Go phim bat ky -> He thong se Echo (gui nguoc lai)\r\n");
    uart_puts("   dong thoi hien thi ma ASCII cua phim do len 8 LED.\r\n");
    uart_puts("2. An phim 't' (thuong) -> Gui mot chuoi test UART dai!\r\n");
    uart_puts("==================================================\r\n\r\n");
    uart_puts("Ready > ");
    
    while (1) {
        // Đọc ký tự từ UART
        int rx_char = uart_getchar_nonblocking();
        
        if (rx_char != -1) {
            char c = (char)rx_char;
            
            // Báo mã ASCII của ký tự gõ lên 8 LED đỏ
            LED_REG = c;
            
            if (c == 't') {
                // Nhấn phím 't' gửi chuỗi test
                uart_puts("\r\n[Chuoi Test UART]: Xin chao tu RISC-V PicoRV32 Core tren DE10-Lite!\r\nReady > ");
            } else if (c == '\r' || c == '\n') {
                // Nhấn Enter xuống dòng
                uart_puts("\r\nReady > ");
            } else {
                // Echo lại ký tự thường
                uart_puts("Ban da go: '");
                uart_putchar(c);
                uart_puts("'\r\nReady > ");
            }
        }
    }
    
    return 0;
}
