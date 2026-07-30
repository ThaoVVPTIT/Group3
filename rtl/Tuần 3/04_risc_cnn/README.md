# Tích hợp PicoRV32 + CNN mẫu trên DE10-Lite

Project này là bản thử tích hợp độc lập. Nó không sửa `Pico`,
`Pico_2` hay `Project_mẫu`.

Mục tiêu của bản này là kiểm chứng đầy đủ đường đi:

```text
PC gửi 784 pixel qua UART
    -> firmware chạy trên PicoRV32
    -> MMIO input buffer
    -> CNN MNIST mẫu của giảng viên
    -> START / BUSY / DONE / RESULT
    -> PicoRV32 gửi kết quả về PC qua UART
```

Đây vẫn là CNN nhận dạng **10 chữ số MNIST** của project mẫu. Nó chưa
phải mạng 47 lớp của đề tài mới và chưa có ESP-CAM. Khi bản này chạy ổn,
giao diện MMIO và firmware có thể được giữ lại để thay lõi CNN mới.

## Kết quả mô phỏng hiện tại

Testbench `sim/cnn_mmio_tb.v` đã nạp vector MNIST đầu tiên ba lần liên
tiếp. Cả ba vòng đều:

- nhận đủ 784 byte;
- đi từ `START` tới `DONE`;
- trả class `3`, đúng với prediction của RTL mẫu;
- hoàn tất sau 1282 chu kỳ;
- tăng `FRAME_ID` lần lượt 1, 2, 3.

Log mô phỏng được lưu tại `reports/modelsim_mmio_3runs.log`.

## Kết quả Quartus 18.1 trên DE10-Lite

Project đã chạy thành công đủ Synthesis, Fitter, TimeQuest và Assembler cho
chip `10M50DAF484C7G`.

| Chỉ tiêu post-fit | Kết quả |
|---|---:|
| Logic elements | 39.083 / 49.760 (79%) |
| Combinational functions | 37.743 / 49.760 (76%) |
| Registers | 13.092 / 49.760 (26%) |
| Memory bits | 270.464 / 1.677.312 (16%) |
| Embedded multiplier 9-bit | 96 / 288 (33%) |
| M9K | 35 |

TimeQuest xác nhận thiết kế đạt clock 50 MHz:

| Kiểm tra xấu nhất | Slack | TNS |
|---|---:|---:|
| Setup, Slow 85 °C | +3,171 ns | 0 |
| Hold, Fast 0 °C | +0,059 ns | 0 |

Không có clock, input, output hoặc timing path nào chưa được ràng buộc. File
`output_files/de10_riscv_cnn_sample.sof` đã được tạo thành công. Tuy nhiên,
file `.sof` hiện tại vẫn chứa firmware UART cũ dùng làm placeholder; phải làm
đúng mục **Sinh firmware trong VMware** rồi compile lại trước khi test trên kit.

Các báo cáo chi tiết đã được tổng hợp tại
`BAO_CAO_KET_QUA_TICH_HOP.md`.

## Cấu trúc thư mục

- `rtl/`: PicoRV32, PicoSoC, lõi CNN mẫu và MMIO controller.
- `data/`: trọng số int8 và vector MNIST dùng để kiểm thử.
- `firmware/`: `main.c`, `start.S`, `sections.lds`, `Makefile`,
  `makehex.py`.
- `host/`: chương trình Python gửi ảnh và kiểm tra kết quả.
- `sim/`: testbench RTL.
- `de10_riscv_cnn_sample.qpf/.qsf/.sdc`: project Quartus DE10-Lite.

## Bản đồ MMIO

Base address: `0x0300_0000`.

| Offset | Tên | Quyền | Ý nghĩa |
|---:|---|---|---|
| `0x00` | `ID_VERSION` | R | `0x434E4E31` (`CNN1`) |
| `0x04` | `CONTROL` | W | bit 0 START, bit 1 CLEAR/ABORT, bit 2 ACK_DONE, bit 8 IRQ_ENABLE |
| `0x08` | `STATUS` | R | bit 0 READY, 1 BUSY, 2 DONE, 3 ERROR, 4 INPUT_FULL |
| `0x0C` | `CONFIG` | R | int8, 10 lớp, 28 x 28 |
| `0x10` | `INPUT_LEN` | R | 784 |
| `0x14` | `INPUT_COUNT` | R | số byte đã nhận |
| `0x18` | `INPUT_DATA8` | W8 | ghi tuần tự từng pixel |
| `0x1C` | `RESULT_CLASS` | R | class 0..9 |
| `0x20` | `CYCLE_COUNT` | R | độ trễ từ START tới kết quả |
| `0x24` | `ERROR_CODE` | R | mã lỗi controller |
| `0x28` | `FRAME_ID` | R | tăng sau mỗi inference thành công |

`DONE` và `ERROR` là sticky: phần mềm đọc được cho đến khi ghi
`CONTROL.CLEAR`.

## Sinh firmware trong VMware

Copy nguyên thư mục `firmware` sang Ubuntu VM rồi chạy:

```bash
make clean
make
wc -l firmware.hex
```

Kết quả đúng phải có `8192 firmware.hex`, tương ứng RAM 32 KiB. Copy
file vừa sinh về thư mục gốc của project này với đúng tên:

```text
DE10_RISCV_CNN_SAMPLE/firmware.hex
```

Không cần sinh `de10_sections.lds` hay đổi tên linker script. Các thông
số đã đồng bộ trực tiếp: `MEM_WORDS=8192`, linker RAM `0x8000`, và
`makehex.py` xuất 8192 word.

Lưu ý: `firmware.hex` đang có trong thư mục gốc ban đầu chỉ là firmware
UART cũ dùng làm dữ liệu tạm để Quartus đo tài nguyên. Trước khi nạp kit,
phải thay nó bằng firmware sinh từ `firmware/main.c` trong project này.

## Mở Quartus

Đường dẫn `E:\InterTT` hiện chỉ dùng ký tự ASCII nên có thể mở project trực tiếp. Nếu muốn dùng ổ `Q:` để giữ tương thích với lệnh cũ, tạo ổ tạm:

```powershell
subst Q: "E:\InterTT\DE10_RISCV_CNN_SAMPLE"
```

Sau đó mở:

```text
Q:\de10_riscv_cnn_sample.qpf
```

Compile lại sau mỗi lần thay `firmware.hex`, vì firmware được khởi tạo
trực tiếp vào BRAM của FPGA.

## Test trên kit

1. Program `output_files/de10_riscv_cnn_sample.sof`.
2. Nối USB-UART 3.3 V: TX adapter vào `W8` (UART_RX), RX adapter vào
   `W9` (UART_TX), và nối chung GND.
3. Cài PySerial nếu máy chưa có:

   ```powershell
   python -m pip install pyserial
   ```

4. Chạy:

   ```powershell
   python host/test_riscv_cnn.py --port COM3 --repeat 3 --expected 3
   ```

5. Nhấn và thả `KEY[0]` khi chương trình yêu cầu.

Kết quả đạt phải là ba dòng `PASS`, class luôn bằng 3 và cycle count
không đổi giữa các lần chạy.

## LED debug

- `LEDR[3:0]`: class kết quả.
- `LEDR[4]`: DONE.
- `LEDR[5]`: BUSY.
- `LEDR[6]`: ERROR.
- `LEDR[7]`: input đã đủ 784 byte.
- `LEDR[8]`: reset đã được thả.
- `LEDR[9]`: heartbeat 50 MHz.

