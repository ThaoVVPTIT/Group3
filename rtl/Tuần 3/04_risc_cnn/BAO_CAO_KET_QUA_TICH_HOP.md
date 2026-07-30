# Báo cáo kết quả tích hợp PicoRV32 với CNN MNIST mẫu trên DE10-Lite

## 1. Kết luận

Bản tích hợp độc lập đã hoàn thành ở mức RTL, mô phỏng và biên dịch Quartus:

- PicoRV32 truy cập lõi CNN qua MMIO.
- Bộ đệm nhận đủ 784 pixel `uint8`.
- Luồng điều khiển `START -> BUSY -> DONE -> RESULT` hoạt động lặp lại.
- RTL CNN mẫu trả class `3` cho vector kiểm thử số 0, đúng prediction của
  project gốc.
- Fitter đặt và route thành công trên MAX10 `10M50DAF484C7G`.
- TimeQuest đạt 50 MHz với setup/hold slack dương và không có đường timing
  chưa ràng buộc.
- Quartus Assembler đã tạo được file `.sof`.

Điều chưa thể xác nhận trên máy này là phép thử vật lý qua cổng UART của kit.
Trước phép thử đó, cần build firmware tích hợp trong VMware và compile lại
Quartus vì `.sof` hiện tại vẫn dùng firmware UART cũ làm placeholder.

## 2. Phạm vi

Project mới nằm riêng tại `E:\InterTT\DE10_RISCV_CNN_SAMPLE`; không sửa
`Pico`, `Pico_2` hoặc `Project_mẫu`.

CNN được giữ đúng phạm vi project mẫu:

```text
28x28x1
  -> Conv1 5x5, 3 kênh
  -> MaxPool + ReLU
  -> Conv2 5x5, 3 vào / 3 ra
  -> MaxPool + ReLU
  -> Fully Connected 48 -> 10
  -> Comparator -> class 0..9
```

Đây là bài kiểm chứng tích hợp cho 10 chữ số MNIST. Nó chưa phải CNN 47 đầu
ra của đề tài mới và chưa nhận ảnh trực tiếp từ ESP-CAM.

## 3. Kiến trúc tích hợp

```text
PC/Python
   |  UART 115200, 784 raw bytes
   v
PicoRV32 + firmware
   |  MMIO 0x0300_0000
   v
CNN MMIO controller
   |-- input RAM 784 x 8, suy luận thành 1 M9K
   |-- START / READY / BUSY / DONE / ERROR
   |-- cycle counter / frame counter / result
   v
CNN MNIST mẫu
```

Firmware không giữ thêm một bản ảnh trong RAM CPU: mỗi byte UART được ghi
ngay vào RAM đầu vào của accelerator. Cách này giảm áp lực lên RAM 32 KiB và
phù hợp hơn khi sau này thay lõi CNN lớn hơn.

## 4. Bản đồ thanh ghi MMIO

Base address: `0x0300_0000`.

| Offset | Thanh ghi | Truy cập | Nội dung |
|---:|---|---|---|
| `0x00` | `ID_VERSION` | R | `0x434E4E31`, chuỗi `CNN1` |
| `0x04` | `CONTROL` | W | bit 0 START, bit 1 CLEAR/ABORT, bit 2 ACK_DONE, bit 8 IRQ_ENABLE |
| `0x08` | `STATUS` | R | READY, BUSY, DONE, ERROR, INPUT_FULL |
| `0x0C` | `CONFIG` | R | int8, 10 lớp, 28 x 28 |
| `0x10` | `INPUT_LEN` | R | 784 |
| `0x14` | `INPUT_COUNT` | R | số pixel đã ghi |
| `0x18` | `INPUT_DATA8` | W8 | pixel kế tiếp |
| `0x1C` | `RESULT_CLASS` | R | class 0..9 |
| `0x20` | `CYCLE_COUNT` | R | độ trễ START đến kết quả |
| `0x24` | `ERROR_CODE` | R | mã lỗi controller |
| `0x28` | `FRAME_ID` | R | tăng sau mỗi inference thành công |

`DONE` và `ERROR` được giữ lại để phần mềm không bỏ lỡ xung kết quả.
`CONTROL.CLEAR` xóa trạng thái, đặt lại con trỏ ảnh và reset pipeline CNN.

## 5. Các thay đổi kỹ thuật quan trọng

### 5.1. Giữ nguyên thuật toán CNN mẫu

Các file RTL CNN chỉ được đổi đường dẫn `$readmemh` sang thư mục `data/`.
Không thay đổi phép toán, trọng số, bias, kích thước kernel hay pipeline của
CNN.

### 5.2. Bộ đệm ảnh dùng M9K

Bản đầu để mảng `784 x 8` bên trong FSM khiến Quartus triển khai bộ đệm bằng
6.272 flip-flop và logic chọn lớn. Synthesis khi đó dùng 54.598 logic
elements, vượt 49.760 LE của chip.

Bộ đệm sau đó được tách thành RAM đồng bộ hai cổng đơn giản
`rtl/cnn_input_ram.v`. Quartus nhận đúng một M9K 784 x 8. Đồng thời PicoRV32
được cấu hình `rv32i`, tắt multiplier/divider/compressed/counter phần cứng mà
firmware này không cần.

Kết quả logic giảm 12.900 LE ở synthesis, từ 54.598 xuống 41.698
(xấp xỉ 23,6%).

### 5.3. RAM firmware đồng bộ 32 KiB

Ba thông số khớp nhau:

- `picosoc.MEM_WORDS = 8192`;
- linker script có độ dài RAM `0x8000`;
- `makehex.py` xuất 8192 word.

Vì `8192 x 4 byte = 32768 byte = 32 KiB`, không còn ánh xạ lặp do bus địa chỉ
11 bit như bản 8 KiB cũ.

## 6. Kết quả mô phỏng

Testbench `sim/cnn_mmio_tb.v` ghi 784 pixel qua đúng giao diện MMIO rồi chạy
ba inference liên tiếp:

| Lần | Class | Chu kỳ | Frame ID | Kết quả |
|---:|---:|---:|---:|---|
| 1 | 3 | 1282 | 1 | PASS |
| 2 | 3 | 1282 | 2 | PASS |
| 3 | 3 | 1282 | 3 | PASS |

Kết luận: controller có thể tái sử dụng sau mỗi frame; START, DONE, result và
frame counter ổn định. Log gốc nằm tại `reports/modelsim_mmio_3runs.log`.

## 7. Kết quả Quartus post-fit

Quartus Prime 18.1 Lite, chip `10M50DAF484C7G`:

| Tài nguyên | Sử dụng | Tỷ lệ |
|---|---:|---:|
| Logic elements | 39.083 / 49.760 | 79% |
| Combinational functions | 37.743 / 49.760 | 76% |
| Dedicated logic registers | 13.092 / 49.760 | 26% |
| Memory bits | 270.464 / 1.677.312 | 16% |
| M9K | 35 | — |
| Embedded multiplier 9-bit | 96 / 288 | 33% |
| Pins | 25 / 360 | 7% |

Placement và routing đều thành công. Router ước lượng interconnect trung bình
29%, đỉnh 53%.

## 8. Kết quả timing 50 MHz

Clock `MAX10_CLK1_50` được ràng buộc chu kỳ 20,000 ns.

| Corner | Kiểm tra | Slack | TNS |
|---|---|---:|---:|
| Slow 85 °C | Setup | +3,171 ns | 0 |
| Slow 85 °C | Hold | +0,182 ns | 0 |
| Slow 0 °C | Setup | +4,559 ns | 0 |
| Slow 0 °C | Hold | +0,194 ns | 0 |
| Fast 0 °C | Setup | +12,723 ns | 0 |
| Fast 0 °C | Hold | +0,059 ns | 0 |

TimeQuest báo 0 unconstrained clock, 0 unconstrained input/output port và
thiết kế fully constrained cho cả setup lẫn hold.

Cảnh báo I/O duy nhất là chưa chỉ định drive strength cho `UART_TX` và LED.
Vị trí chân và chuẩn điện áp 3,3 V đã được gán; Quartus dùng drive strength
mặc định.

## 9. Việc cần làm để test trên kit

1. Copy thư mục `firmware/` sang Ubuntu VMware.
2. Chạy:

   ```bash
   make clean
   make
   wc -l firmware.hex
   ```

3. Xác nhận kết quả là `8192 firmware.hex`.
4. Chép file đó đè vào
   `E:\InterTT\DE10_RISCV_CNN_SAMPLE\firmware.hex`.
5. Mở `Q:\de10_riscv_cnn_sample.qpf` sau khi tạo ổ Q bằng `subst`, rồi
   compile lại.
6. Nạp `.sof`, nối USB-UART 3,3 V: TX adapter -> W8, RX adapter -> W9,
   nối chung GND.
7. Chạy:

   ```powershell
   python host/test_riscv_cnn.py --port COM3 --repeat 3 --expected 3
   ```

8. Nhấn và thả `KEY[0]` theo lời nhắc.

Phép thử đạt khi cả ba lần trả class 3, cycle count không đổi, frame ID tăng
1, 2, 3 và script kết thúc `FINAL: 3/3 repeat tests passed`.

## 10. Ý nghĩa đối với project 47 đầu ra

Bản này tách rủi ro tích hợp khỏi rủi ro thuật toán. Khi nó chạy đúng trên
kit, các phần đã được kiểm chứng có thể giữ lại gồm PicoRV32, UART, giao thức
MMIO, trạng thái START/BUSY/DONE/ERROR, bộ đếm frame và khung chương trình PC.

Khi thay lõi 10 lớp bằng lõi 47 lớp, cần cập nhật ít nhất:

- trường số lớp trong `CONFIG`;
- độ rộng và quy ước `RESULT_CLASS`;
- kích thước/định dạng ảnh nếu ESP-CAM không xuất đúng 28 x 28 uint8;
- giao thức nạp trọng số nếu trọng số không còn cố định bằng `$readmemh`;
- ước lượng lại LE, M9K, DSP và timing.

DE10-Lite hiện còn khoảng 21% logic sau fit, nên bản CNN 47 đầu ra không thể
được mặc định là sẽ vừa chip. Cần compile sớm lõi mới và đo post-fit trước
khi hoàn thiện phần camera hoặc firmware nâng cao.
