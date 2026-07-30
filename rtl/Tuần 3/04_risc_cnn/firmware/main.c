#include <stdint.h>

#define UART_DATA (*(volatile int32_t  *)0x02000008)
#define UART_DIV  (*(volatile uint32_t *)0x02000004)

#define CNN_BASE         0x03000000u
#define CNN_ID_VERSION   (*(volatile uint32_t *)(CNN_BASE + 0x00u))
#define CNN_CONTROL      (*(volatile uint32_t *)(CNN_BASE + 0x04u))
#define CNN_STATUS       (*(volatile uint32_t *)(CNN_BASE + 0x08u))
#define CNN_CONFIG       (*(volatile uint32_t *)(CNN_BASE + 0x0Cu))
#define CNN_INPUT_LEN    (*(volatile uint32_t *)(CNN_BASE + 0x10u))
#define CNN_INPUT_COUNT  (*(volatile uint32_t *)(CNN_BASE + 0x14u))
#define CNN_INPUT_DATA8  (*(volatile uint8_t  *)(CNN_BASE + 0x18u))
#define CNN_RESULT_CLASS (*(volatile uint32_t *)(CNN_BASE + 0x1Cu))
#define CNN_CYCLE_COUNT  (*(volatile uint32_t *)(CNN_BASE + 0x20u))
#define CNN_ERROR_CODE   (*(volatile uint32_t *)(CNN_BASE + 0x24u))
#define CNN_FRAME_ID     (*(volatile uint32_t *)(CNN_BASE + 0x28u))

#define CNN_CONTROL_START      (1u << 0)
#define CNN_CONTROL_CLEAR_ALL  (1u << 1)
#define CNN_STATUS_READY       (1u << 0)
#define CNN_STATUS_BUSY        (1u << 1)
#define CNN_STATUS_DONE        (1u << 2)
#define CNN_STATUS_ERROR       (1u << 3)
#define CNN_STATUS_INPUT_FULL  (1u << 4)

#define CNN_EXPECTED_ID 0x434E4E31u
#define IMAGE_SIZE      784u
#define POLL_TIMEOUT    10000000u

static void uart_init(void)
{
    UART_DIV = 434; // 50 MHz / 115200 baud, rounded.
}

static void uart_write_raw(uint8_t value)
{
    UART_DATA = value;
}

static void uart_putchar(char c)
{
    if (c == '\n')
        uart_write_raw('\r');
    uart_write_raw((uint8_t)c);
}

static void uart_puts(const char *text)
{
    while (*text)
        uart_putchar(*text++);
}

static uint8_t uart_getchar_blocking(void)
{
    int32_t value;
    do {
        value = UART_DATA;
    } while (value < 0);
    return (uint8_t)value;
}

static void uart_put_hex4(uint8_t value)
{
    value &= 0x0f;
    uart_putchar((value < 10) ? ('0' + value) : ('A' + value - 10));
}

static void uart_put_hex8(uint8_t value)
{
    uart_put_hex4(value >> 4);
    uart_put_hex4(value);
}

static void uart_put_hex32(uint32_t value)
{
    int shift;
    for (shift = 28; shift >= 0; shift -= 4)
        uart_put_hex4((uint8_t)(value >> shift));
}

static void uart_put_dec(uint32_t value)
{
    char digits[10];
    int count = 0;

    if (value == 0) {
        uart_putchar('0');
        return;
    }

    while (value != 0) {
        digits[count++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (count != 0)
        uart_putchar(digits[--count]);
}

static void print_accelerator_error(const char *prefix)
{
    uart_puts(prefix);
    uart_puts(" STATUS=0x");
    uart_put_hex32(CNN_STATUS);
    uart_puts(" CODE=0x");
    uart_put_hex32(CNN_ERROR_CODE);
    uart_putchar('\n');
}

int main(void)
{
    uint32_t i;
    uint32_t status;
    uint32_t timeout;
    uint32_t sum;
    uint8_t xor_value;
    uint8_t pixel;

    uart_init();
    uart_puts("\n=== PICORV32 + CNN SAMPLE INTEGRATION ===\n");
    uart_puts("CNN_ID=0x");
    uart_put_hex32(CNN_ID_VERSION);
    uart_puts(" CONFIG=0x");
    uart_put_hex32(CNN_CONFIG);
    uart_putchar('\n');

    if (CNN_ID_VERSION != CNN_EXPECTED_ID) {
        uart_puts("FATAL: CNN MMIO ID MISMATCH\n");
        while (1) {
        }
    }

    while (1) {
        CNN_CONTROL = CNN_CONTROL_CLEAR_ALL;

        if ((CNN_INPUT_LEN != IMAGE_SIZE) || (CNN_INPUT_COUNT != 0u)) {
            print_accelerator_error("FATAL: CNN CLEAR FAILED");
            while (1) {
            }
        }

        sum = 0;
        xor_value = 0;
        uart_puts("READY 784\n");

        // The PC sends exactly 784 raw uint8 pixels. Each byte is forwarded
        // immediately through PicoRV32 MMIO into the accelerator input RAM.
        for (i = 0; i < IMAGE_SIZE; ++i) {
            pixel = uart_getchar_blocking();
            CNN_INPUT_DATA8 = pixel;
            sum += pixel;
            xor_value ^= pixel;
        }

        uart_puts("RX SUM=0x");
        uart_put_hex32(sum);
        uart_puts(" XOR=0x");
        uart_put_hex8(xor_value);
        uart_putchar('\n');

        status = CNN_STATUS;
        if ((CNN_INPUT_COUNT != IMAGE_SIZE) ||
            ((status & (CNN_STATUS_READY | CNN_STATUS_INPUT_FULL)) !=
             (CNN_STATUS_READY | CNN_STATUS_INPUT_FULL))) {
            print_accelerator_error("ERROR: INPUT BUFFER");
            continue;
        }

        CNN_CONTROL = CNN_CONTROL_START;

        timeout = POLL_TIMEOUT;
        do {
            status = CNN_STATUS;
            if (status & (CNN_STATUS_DONE | CNN_STATUS_ERROR))
                break;
        } while (--timeout != 0u);

        if (timeout == 0u) {
            uart_puts("ERROR: SOFTWARE POLL TIMEOUT\n");
            continue;
        }

        if (status & CNN_STATUS_ERROR) {
            print_accelerator_error("ERROR: CNN");
            continue;
        }

        uart_puts("RESULT CLASS=");
        uart_put_dec(CNN_RESULT_CLASS & 0x0fu);
        uart_puts(" CYCLES=");
        uart_put_dec(CNN_CYCLE_COUNT);
        uart_puts(" FRAME=");
        uart_put_dec(CNN_FRAME_ID);
        uart_puts(" STATUS=0x");
        uart_put_hex32(status);
        uart_putchar('\n');
    }
}
