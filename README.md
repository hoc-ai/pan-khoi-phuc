# PAN – trang khôi phục máy chủ

Dùng khi máy chủ PAN cũ hỏng hẳn. Trên VPS Ubuntu mới (22.04 / 24.04), đăng nhập SSH bằng root rồi dán:

```
curl -fsSL https://raw.githubusercontent.com/hoc-ai/pan-khoi-phuc/main/khoi-phuc.sh | sudo bash
```

Lệnh in ra địa chỉ `https://<IP>:8443/?ma=...` → mở trên trình duyệt → chọn tệp **Bộ khôi phục** (tải từ trang *Sao lưu máy chủ* lúc máy cũ còn chạy) → chọn bản sao lưu → **Khôi phục**.

Tệp này không chứa bí mật nào: khóa vào nơi lưu và mật khẩu giải mã chỉ nằm trong tệp Bộ khôi phục.
