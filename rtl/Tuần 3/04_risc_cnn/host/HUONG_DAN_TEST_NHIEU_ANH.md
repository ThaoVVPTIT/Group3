# Hướng dẫn kiểm thử nhiều ảnh qua PicoRV32 + CNN

## Mục tiêu

Bài test một ảnh lặp ba lần chỉ kiểm tra tính ổn định. Script
`test_riscv_cnn_batch.py` gửi nhiều ảnh khác nhau, đọc nhãn thật và tách riêng
hai loại kết quả:

- `MODEL=OK/MISS`: CNN dự đoán đúng hay sai so với nhãn.
- `PROTOCOL=OK/FAIL`: UART, MMIO, cycle count, frame ID và trạng thái phần
  cứng có ổn định hay không.

Một ảnh `MODEL=MISS` chưa chắc là lỗi RISC-V. Nếu `PROTOCOL=OK`, dữ liệu và
trình tự điều khiển vẫn đúng; sai số có thể đến từ mô hình CNN.

## Kết nối

```text
TX adapter -> W8 (UART_RX của FPGA)
RX adapter -> W9 (UART_TX của FPGA)
GND        -> GND chung
```

## Bước 1 - kiểm tra dữ liệu mà chưa mở UART

```powershell
cd "E:\Quartus\Project_Quartus\04_risc_cnn"
python host\test_riscv_cnn_batch.py --dry-run --count 20
```

Lệnh này xác nhận file ảnh, file nhãn, phạm vi index và checksum.

## Bước 2 - chạy 20 ảnh đầu tiên

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --count 20
```

Thay `COM3` bằng cổng USB-UART thật. Khi được yêu cầu, giữ `KEY[0]` khoảng
0,2 giây, thả nút rồi nhấn Enter.

Hai cột quan trọng:

```text
MODEL=OK/MISS
PROTOCOL=OK/FAIL
```

Kết quả tích hợp đạt khi cuối log có:

```text
Protocol errors : 0
CNN cycles      : min=1282 max=1282
FINAL: HARDWARE/PROTOCOL PASS
```

## Bước 3 - chạy 100 ảnh

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --count 100
```

## Bước 4 - chạy toàn bộ 1.000 ảnh

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --count 1000
```

Kết quả từng ảnh được lưu tại:

```text
reports\hardware_batch_results.csv
```

## Chạy một đoạn khác của bộ dữ liệu

Ví dụ ảnh 200 đến 249:

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --start 200 --count 50
```

## Xem toàn bộ dòng phản hồi từ FPGA

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --count 20 --verbose
```

## Khi cycle count thay đổi có chủ ý

Giá trị chuẩn hiện tại là 1282. Nếu sửa kiến trúc CNN và chỉ muốn kiểm tra
cycle có ổn định hay không, có thể tắt kiểm tra chính xác:

```powershell
python host\test_riscv_cnn_batch.py --port COM3 --count 20 --expected-cycles -1
```
