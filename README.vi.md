# MicroScale

[![Giấy phép](https://img.shields.io/github/license/nghianguyen150612/MicroScale)](LICENSE)
[![Phiên bản](https://img.shields.io/github/v/release/nghianguyen150612/MicroScale?include_prereleases)](https://github.com/nghianguyen150612/MicroScale/releases)
[![Build](https://github.com/nghianguyen150612/MicroScale/actions/workflows/build.yml/badge.svg)](https://github.com/nghianguyen150612/MicroScale/actions/workflows/build.yml)

**Tailscale, built smaller.** Ba cấu hình build Tailscale tối ưu dung lượng cho OpenWrt và Linux, không cần fork mã nguồn upstream.

[English](README.md) | **Tiếng Việt**

> Mã nguồn gốc: [Tailscale](https://github.com/tailscale/tailscale). MicroScale là dự án đóng gói độc lập, không phải bản phát hành chính thức của Tailscale.

## Vì sao chọn MicroScale?

Các router thường có flash và RAM hạn chế. MicroScale đóng gói CLI cùng daemon Tailscale, hỗ trợ tải xuống có SHA256, chạy thử hoàn toàn trong RAM hoặc cài binary lâu dài khi người dùng chủ động lựa chọn.

## Tính năng

- **Small, Micro, Extreme** — đầy đủ tính năng, rút gọn tính năng, hoặc rút gọn kèm UPX.
- **ARM64 và x86_64** — sáu gói binary trong mỗi release.
- **Cài đặt một lệnh** — menu chọn profile, có lệnh quản lý ngắn `microscale`.
- **Bootstrap có kiểm tra SHA256** — chỉ chạy manager sau khi xác minh file.
- **Quản lý vòng đời** — cài, cập nhật, repair, status, diagnostics, doctor và uninstall.
- **Cài vào RAM trước** — lưu binary đã kiểm tra SHA256 tại `/tmp/microscale-stage`; chạy lại installer để áp dụng chính binary này vào NAND.
- **Test RAM thống nhất** — dùng `test-ram` trên router thật và VM, kiểm tra bản đã stage hoặc binary tải về, ghi TSV cho từng lần chạy.
- **Lưu kết quả lên repo** — máy Arch thu log qua SSH và mở PR, không cần GitHub token trên router.
- **Không cấu hình VPN** — không can thiệp DNS, firewall, route, dịch vụ hoặc Tailscale state.

## Bắt đầu nhanh

> Cần OpenWrt **ARM64**, SSH qua LAN, quyền root, HTTPS và đủ dung lượng overlay. Đọc phần [tương thích](#khả-năng-tương-thích) trước khi cài.

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.2/install.sh && sh /tmp/microscale-install.sh
```

Chọn **Install to RAM**, tiếp đến chọn Small, Micro hoặc Extreme. Thử bản đang nằm trong RAM:

```sh
/tmp/microscale-stage/bin/tailscale version
/tmp/microscale-stage/bin/tailscaled --version
```

**Chạy lại lệnh installer**. Khi bản RAM còn nguyên checksum, menu sẽ thêm mục **Apply RAM to NAND**. Chỉ bước này (hoặc chọn cài thẳng NAND) mới thay binary hệ thống. Manager không restart hay cấu hình Tailscale.

Sau khi apply vào NAND, có thể gọi trực tiếp:

```sh
microscale
microscale help
microscale version
microscale status
microscale doctor
```

Installer **không tự bật/restart Tailscale**. Người dùng tự quyết định cách khởi chạy và cấu hình VPN.

## Kiến trúc installer

```text
install.sh (bootstrap được ghim phiên bản)
   │ tải → xác minh SHA256 → chạy
   ▼
manager.sh (POSIX shell)
   ├── /usr/lib/microscale/manager.sh
   ├── /usr/bin/microscale → /usr/lib/microscale/manager.sh
   ├── /etc/microscale/ (trạng thái + bản sao binary gốc)
   ├── /usr/sbin/tailscaled
   └── /usr/bin/tailscale → /usr/sbin/tailscaled
```

Trạng thái của MicroScale nằm tại `/etc/microscale`, phù hợp hơn với OpenWrt. Bộ quản lý là script trong `/usr/lib`, còn `microscale` chỉ là symlink. Không chạm vào file cấu hình hay state của chính Tailscale.

## Quản lý bằng CLI

```sh
microscale install-ram micro
microscale ram-status
microscale test-ram staged
microscale test-ram all
microscale report
microscale apply   # Ghi bản đã xác minh từ RAM vào NAND
microscale clear-ram
microscale install micro
microscale update micro
microscale repair
microscale status
microscale diagnostics
microscale doctor
microscale version
microscale uninstall
```

Bản cài RAM chỉ ghi vào `/tmp` (tmpfs), mất sau reboot. Các thao tác ghi NAND yêu cầu root và xác nhận tương tác. Uninstall phục hồi binary ban đầu, giữ nguyên toàn bộ cấu hình VPN. Xem [chi tiết installer](docs/ONE-CLICK-INSTALL.md).

## Ba mức tối ưu

| Profile | Cách build | ELF ARM64* |
| --- | --- | ---: |
| **Small** | Đầy đủ tính năng, combined + strip | 40.00 MiB |
| **Micro** | Rút gọn nhưng tương thích NR3053 | 19.63 MiB |
| **Extreme** | Micro + UPX | 5.08 MiB |

*Kết quả đo từ Tailscale v1.104.5. Kích thước ELF khác dung lượng chiếm dụng thực tế trên NAND UBIFS.*

## Khả năng tương thích

| Môi trường | Mức kiểm chứng |
| --- | --- |
| NR3053, OpenWrt ARM64 | **Micro v0.2.2: userspace, SOCKS5, SSH prefs, 5 cổng Serve và reboot router PASS** |
| NR3053 — Exit Node, uptime 24 giờ | **Chưa kiểm chứng** (Exit Node đã chủ động tắt) |
| Linux x86_64 | Build và smoke test CI PASS, chưa thử VM 500 MiB |
| Kiến trúc khác | Chưa có gói phát hành |

[Log test NR3053](reports/openwrt-arm64-2026-11-03-rc4.md) cho thấy Micro có mức RSS CLI thấp nhất trong lượt đo đó. Đây không phải kết quả RAM daemon 24/7.

**Lưu ý NR3053 (v0.2.2):** Profile rút gọn cũ thiếu `netstack` và
`outboundproxy`, khiến dịch vụ Tailscale dạng userspace trên router không thể
khởi động và làm mất SOCKS5. NR3053 còn dùng Tailscale Serve, SSH và cần Health tracker để hiển thị trạng thái online chính xác.
Micro/Extreme v0.2.2 đã giữ lại những tính năng này qua feature tags upstream.
**Binary v0.2.1 cũ không phù hợp với NR3053.** Bản Micro đã chạy thử thành công
trên router với SOCKS5, VPN, Serve và tùy chọn SSH sau khi restart riêng dịch vụ.
Đã PASS sau khi reboot router thật; chưa đủ bằng chứng uptime 24 giờ. Binary gốc được giữ trên Arch để rollback.


## Thử trong RAM mà không cài đặt

Có thể dùng **Install to RAM** để thử trước rồi Apply sang NAND, hoặc dùng [`ram-test.sh`](docs/RAM-TEST.md) để tự động đo CLI trong tmpfs. Cả hai không thay daemon hệ thống.

## Cộng đồng kiểm thử thiết bị thật

**Ai cũng có thể gửi log, không cần quyền push vào repo.** Script tự tạo hoặc dùng fork GitHub và mở Pull Request để đóng góp kết quả.

```bash
gh auth login
gh auth setup-git
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash scripts/collect-device-report.sh --submit --device "Tên thiết bị (không bắt buộc)" root@ROUTER_IP all
```

Nếu đã có `latest.tsv`, dùng `bash scripts/import-report.sh --submit /đường/dẫn/latest.tsv`. Dữ liệu được kiểm tra và chỉ đưa vào `main` sau khi maintainer review. Xem [hướng dẫn đóng góp](CONTRIBUTING.md) và [báo cáo cộng đồng](reports/community/README.md). **PASS CLI không có nghĩa là VPN/Exit Node đã được kiểm chứng.**

## Tự build

```sh
TARGET_GOARCH=arm64 bash scripts/build.sh micro
TARGET_GOARCH=amd64 bash scripts/build.sh micro
```

## Giấy phép

MicroScale duy trì code đóng gói riêng. Binary Tailscale vẫn phải tuân thủ giấy phép và thông báo bản quyền của upstream. Xem [third-party notices](THIRD_PARTY_NOTICES.md).
