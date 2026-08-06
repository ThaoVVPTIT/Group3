# PicoRV32 + CNN qua AXI4-Lite (DE10-Lite)

Project này là bản AXI4-Lite độc lập của `04_risc_cnn`. Bản cũ không bị sửa.

## Kiến trúc

`picorv32_axi` (AXI4-Lite master) -> `axi4lite_soc_slave` -> RAM / UART / CNN / GPIO.

`cnn_accel_core` giữ nguyên luồng CNN mẫu và register map của firmware. Vì vậy
firmware và chương trình Python hiện tại vẫn dùng được, nhưng mọi lần đọc/ghi của
CPU bây giờ đi qua năm kênh chuẩn AXI4-Lite: AW, W, B, AR và R.

## Bản đồ địa chỉ

| Vùng | Địa chỉ | Chức năng |
|---|---:|---|
| RAM | `0x00000000` - `0x00007FFF` | 32 KiB firmware/data |
| UART divisor | `0x02000004` | Cấu hình baud |
| UART data | `0x02000008` | Truyền/nhận byte |
| CNN | `0x03000000` - `0x030000FF` | Thanh ghi điều khiển CNN |
| GPIO | `0x04000000` | Đọc `SW[9:0]` |

Các thanh ghi CNN quan trọng:

| Offset | Thanh ghi | Truy cập |
|---:|---|---|
| `0x00` | ID_VERSION | Read |
| `0x04` | CONTROL: bit0 START, bit1 CLEAR_ALL | Write |
| `0x08` | STATUS: READY/BUSY/DONE/ERROR/INPUT_FULL | Read |
| `0x18` | INPUT_DATA8 | Write byte |
| `0x1C` | RESULT_CLASS | Read |
| `0x20` | CYCLE_COUNT | Read |
| `0x28` | FRAME_ID | Read |

## Mở và nạp bằng Quartus

1. Mở `de10_riscv_cnn_axi.qpf` bằng Quartus Prime 18.1.
2. Chạy **Processing -> Start Compilation**.
3. Nạp `output_files/de10_riscv_cnn_axi.sof` vào DE10-Lite.
4. Nối USB-UART 3.3 V: TX adapter -> W8, RX adapter -> W9 và nối chung GND.
5. Chạy chương trình trong `host/test_riscv_cnn.py` như project 04.

Ví dụ:

```powershell
python host\test_riscv_cnn.py --port COM3 --repeat 3 --expected 3
```

## Các kiểm thử đã chạy

- `sim/axi4lite_cnn_tb.v`: kiểm tra độc lập AXI AW/W/B/AR/R, RAM, GPIO và ba
  chu kỳ CNN START -> BUSY -> DONE. Kết quả: PASS 3/3.
- `sim/top_axi_boot_tb.v`: chạy đúng CPU `picorv32_axi`, fetch firmware từ RAM
  qua AXI và giải mã UART. Kết quả: boot tới `READY 784`, `cpu_trap=0`.
- Quartus full compilation: thành công, tạo file SOF.
- Timing 50 MHz: setup slack xấu nhất `+3.812 ns`, hold slack `+0.147 ns`;
  thiết kế đạt timing.

Tài nguyên sau Fitter: 38,885/49,760 logic elements (78%), 270,464 memory bits
(16%) và 96/288 multiplier 9-bit (33%).

## File chính

- `rtl/top_axi.v`: top DE10-Lite và PicoRV32 AXI master.
- `rtl/axi4lite_soc_slave.v`: AXI4-Lite slave, decoder RAM/UART/CNN/GPIO.
- `rtl/cnn_accel_core.v`: register bank và điều khiển CNN.
- `firmware/main.c`: firmware điều khiển CNN qua địa chỉ memory-mapped.
- `de10_riscv_cnn_axi.qsf`: danh sách source và pin DE10-Lite.

Các file MMIO cũ được giữ trong `legacy_mmio` chỉ để đối chiếu và không nằm
trong danh sách source của Quartus.
