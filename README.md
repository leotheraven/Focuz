# Focuz 🌱

Focuz là ứng dụng theo dõi thói quen và tập trung cho iPhone và Android. Mỗi phiên Focus giúp cây lớn lên. Xu kiếm được từ Focus và thói quen có thể dùng để mở khóa vật phẩm trong vườn hoặc đổi phần thưởng bạn tự đặt.

## Focuz có gì?

- **Focus và nghỉ** — chọn thời lượng, hẹn giờ và nhận cảnh báo khi rời phiên Focus.
- **Thói quen** — đặt lịch theo ngày, đặt lời nhắc, theo dõi chuỗi và xem số lần hoàn thành trong 28 ngày gần nhất.
- **Khu vườn** — nuôi cây qua 100 cấp, mở khóa cây, phông nền và đồ trang trí. Dùng xu để bón phân nếu muốn tăng XP cho cây.
- **Lịch sử** — xem tối đa 20 lượt hoàn thành thói quen và 20 lượt đổi quà gần nhất. Lượt bón phân tính vào lịch sử đổi quà.
- **Tiếng Việt và English** — chuyển ngôn ngữ trong Cài đặt.

## Tải và cài đặt

| Nền tảng | Yêu cầu | Bản build |
| --- | --- | --- |
| iPhone | iOS 17 trở lên | [Build Focuz IPA](https://github.com/leotheraven/Focuz/actions/workflows/build-ipa.yml) |
| Android | Android 8.0 trở lên | [Build Focuz Android APK](https://github.com/leotheraven/Focuz/actions/workflows/build-android.yml) |

Mở một lượt chạy thành công và tải tệp trong mục **Artifacts**.

- **iPhone** — giải nén để lấy `Focuz-unsigned.ipa`. IPA này cần được ký trước khi cài lên iPhone.
- **Android** — giải nén để lấy file `.apk`, mở file trên điện thoại và chọn **Cài đặt**. APK kiểm thử từ GitHub Actions dùng khóa ký tạm cho mỗi lượt build. Nếu cập nhật bản đang cài, hãy dùng APK ký bằng cùng khóa với bản trước.

## Dữ liệu và sao lưu

Focuz lưu thói quen, cài đặt và tiến độ trên thiết bị. Ứng dụng hoạt động ngoại tuyến ngay sau khi cài đặt.

Mở **Cài đặt** để xuất bản sao lưu JSON hoặc khôi phục dữ liệu từ tệp. Bạn có thể dùng bản sao lưu để chuyển dữ liệu giữa iPhone và Android. Bản sao lưu xuất từ Focuz 2.14 cần Focuz 2.14 trở lên để khôi phục.

Tệp JSON có thể chứa tên thói quen, lịch và tiến độ. Hãy giữ riêng tệp này và xuất một bản sao mới trước khi khôi phục, vì thao tác khôi phục thay thế dữ liệu hiện tại.

## Build từ mã nguồn

Cả hai nền tảng được phát triển trên nhánh `main`. iPhone và Android dùng chung hình ảnh và âm báo trong `MamHabit/`.

### iPhone

Mở `MamHabit.xcodeproj` trong Xcode và chọn scheme `MamHabit` để chạy trên Simulator hoặc thiết bị. Lệnh dưới đây xuất IPA chưa ký trên máy Mac có Xcode và iOS SDK.

```bash
bash scripts/build-ipa.sh
```

Tệp đầu ra là `dist/Focuz-unsigned.ipa`.

### Android

Cài JDK 17, Android SDK Platform 35 và Build Tools 35.0.0. Trỏ `JAVA_HOME` và `ANDROID_SDK_ROOT` đến bộ công cụ đã cài trước khi chạy lệnh build.

```bash
bash scripts/build-apk.sh
```

APK được lưu trong `dist/`. Script dùng khóa trong `build/android-signing/` hoặc thư mục do `FOCUZ_ANDROID_SIGNING_DIR` chỉ định. Giữ bản sao khóa ký ở nơi riêng và dùng lại khóa đó cho các lần cập nhật.

### Kiểm thử

Hai lệnh dưới đây kiểm tra quy tắc tính điểm, lưu dữ liệu và khôi phục bản sao lưu trên macOS.

```bash
bash scripts/test-engine.sh
bash scripts/test-store.sh
```

## Cấu trúc dự án

| Thư mục | Nội dung |
| --- | --- |
| `MamHabit/` | Ứng dụng iPhone, hình ảnh và âm báo |
| `FocuzLiveActivity/` | Đồng hồ Focus trên màn hình khóa iPhone |
| `android/` | Ứng dụng Android |
| `Tests/` và `scripts/` | Kiểm thử và build |

Xem [tài liệu hình ảnh](ARTWORK.md) để biết cách tạo tài nguyên cho khu vườn.

## Giấy phép

Dự án hiện chưa có tệp `LICENSE`.
