// main.c - Mã nguồn C tối giản chạy trực tiếp trên DE10-Lite
#include <stdint.h>
#include <stdbool.h>

// Định nghĩa thanh ghi các thiết bị ngoại vi
#define TIMER0              (* (volatile uint32_t *) 0xffff0030 )
#define TIMER1              (* (volatile uint32_t *) 0xffff0034 )
#define UARTTX              (* (volatile uint32_t *) 0xffff0040 )
#define UARTRX              (* (volatile uint32_t *) 0xffff0050 )
#define PORTA               (* (volatile uint32_t *) 0xffff0060 ) // LED[9:0]

#define UART_RX_EMPTY       0x00000100U

// Hàm gửi 1 ký tự qua UART
void print_chr(char ch) {
    while (UARTTX == 0) {
        // Chờ thanh ghi TX rảnh
    }
    UARTTX = ch;
}

// Hàm gửi 1 chuỗi ký tự qua UART
void print_str(const char *p) {
    while (*p != 0) {
        print_chr(*(p++));
    }
}

// Hàm in số thập phân (Decimal) qua UART
void print_dec(unsigned int val) {
    char buffer[10];
    char *p = buffer;
    while (val || p == buffer) {
        *(p++) = val % 10;
        val = val / 10;
    }
    while (p != buffer) {
        print_chr('0' + *(--p));
    }
}

// Hàm in số Hex qua UART
void print_hex(unsigned int val, int digits) {
    int32_t shift = (digits * 4) - 4;
    for (int i = 0; i < digits; i++) {
        print_chr("0123456789ABCDEF"[(val >> shift) & 15]);
        shift -= 4;
    }
}

// Hàm delay cơ bản
void delay(volatile uint32_t count) {
    while (count--) {
        __asm__ volatile ("nop");
    }
}

// Hàm main chính
int main(void) {
    uint32_t led_state = 1;
    int direction = 1; // 1: dịch trái (từ LED 0 -> 9), 0: dịch phải (từ LED 9 -> 0)
    
    // Gửi thông điệp khởi động qua UART
    print_str("PicoRV32 minimal system up and running on DE10-Lite!\r\n");
    print_str("Starting Knight Rider LED scanner effect...\r\n");
    
    while (1) {
        // Xuất ra 10 LED (PORTA điều khiển LEDR[9:0])
        PORTA = led_state & 0x3FF;
        
        // Gửi trạng thái hiện tại qua UART
        print_str("LED State: 0x");
        print_hex(led_state & 0x3FF, 3);
        print_str("\r\n");
        
        // Cập nhật vị trí LED tiếp theo
        if (direction == 1) {
            led_state = led_state << 1;
            if (led_state == 0x200) { // Chân LED 9 (bit 9)
                direction = 0;        // Đảo chiều dịch sang phải
            }
        } else {
            led_state = led_state >> 1;
            if (led_state == 0x001) { // Chân LED 0 (bit 0)
                direction = 1;        // Đảo chiều dịch sang trái
            }
        }
        
        // Delay khoảng 0.2s để chớp tắt nhanh hơn, nhìn đẹp mắt hơn
        delay(700000);
    }
    
    return 0;
}
