# ByteTrail

**Every byte has a source.**

ByteTrail is a local-first macOS storage inspector and cleanup app. It helps explain where disk space is used, lets you review every cleanup candidate, and performs no network requests, telemetry, analytics, cloud classification, or AI processing.

- macOS 13.0 or later
- Apple Silicon and Intel Macs (Universal 2)
- English and Simplified Chinese

> ByteTrail 1.2 is ad-hoc signed and is not yet notarized by Apple. macOS may block the first launch even when the download is intact. Follow the verified first-launch steps below; do not disable Gatekeeper globally.

## Download and verify

Download `ByteTrail.dmg` and `SHA256.txt` from the [latest GitHub Release](https://github.com/LeMat11/ByteTrail/releases/latest). Do not download ByteTrail from an untrusted mirror.

Place both files in the same directory and optionally verify the download in Terminal:

```sh
cd ~/Downloads
shasum -a 256 -c SHA256.txt
```

The expected SHA-256 for ByteTrail 1.2.0 is:

```text
4c8846fff195e6b29cbe01ab6e5b1f2071b56dfb3b3ecf3bfe3c6f2a8e57044e  ByteTrail.dmg
```

Continue only if the result says `ByteTrail.dmg: OK`. A mismatch means the download is incomplete or different from the published release.

## Install

1. Open `ByteTrail.dmg`.
2. Drag **ByteTrail** into the **Applications** folder.
3. Eject the ByteTrail disk image.
4. Open Finder → Applications and launch ByteTrail.

## First launch when macOS blocks the app

Because the current build does not have an Apple Developer ID signature and notarization ticket, macOS may say that the developer cannot be verified or that Apple cannot check the app for malicious software.

Only override the warning when ByteTrail came from this repository's official GitHub Release and its SHA-256 matches.

1. Try to open ByteTrail once, then dismiss the warning.
2. Open **Apple menu → System Settings → Privacy & Security**.
3. Scroll down to **Security**.
4. Find the message that ByteTrail was blocked and click **Open Anyway**.
5. Authenticate with your Mac login password or Touch ID, then confirm **Open**.

The **Open Anyway** option is available for about one hour after a blocked launch attempt. On some macOS versions, Control-clicking ByteTrail in Finder and choosing **Open** also presents a one-time confirmation button.

Do not disable Gatekeeper, lower the Mac's global security policy, or run `sudo`/quarantine-removal commands. If macOS reports that the app is damaged, download it again from the official Release and recheck the SHA-256. Do not bypass the warning when the checksum differs.

Apple's current guidance: [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).

## Use ByteTrail

1. Start a scan. ByteTrail analyzes supported locations locally and shows findings without changing them.
2. Review the source, path, size, confidence, risk, and cleanup explanation for each finding.
3. Select only the items you recognize and want to act on.
4. Choose **Clean Up Selected**.

Cleanup always has these two visible stages: **Review**, then **Clean Up**. There is no automatic cleanup, background cleanup, or command-line cleanup trigger.

ByteTrail 1.2 can identify:

- Installed applications and their application-bundle sizes
- Exact `~/Library/Caches/<Bundle ID>` matches for installed apps
- Downloaded `.dmg` and `.pkg` installers
- Conservative, Bundle-ID-shaped possible uninstall leftovers
- Large files in Downloads and folders you explicitly select
- Supported caches, logs, developer-tool data, iOS backups, and Trash contents

Possible leftovers are suggestions, not proof that a file is unused. They are always marked for review and never selected automatically.

## What cleanup means

The downloadable Release build can perform real cleanup after you explicitly select an eligible item. It does not permanently erase files:

- Eligible items normally move to the macOS Trash.
- Some ordinary items may move to ByteTrail's recoverable vault when Trash is unavailable.
- Application bundles fail safely if they cannot be moved to Trash.
- System applications, ByteTrail itself, running applications, protected personal data, links that escape an approved path, and changed or invalid targets are blocked.
- ByteTrail never empties Trash automatically. Disk space used by an item in Trash is released only after you empty Trash yourself.

The Xcode Debug build is intentionally different: dry-run is enabled by default, and its development safety lock prevents modification of real user paths.

## Permissions

ByteTrail uses normal macOS user permissions and does not install a privileged helper. macOS privacy controls may prevent access to locations such as Trash or device backups. If a source cannot be read, ByteTrail reports or skips it rather than bypassing macOS protections.

## Privacy

All scanning, attribution, sizing, history, and cleanup decisions happen locally on your Mac. ByteTrail does not contain a network client integration and does not upload file paths, installed-app lists, scan results, cleanup history, or recovery records.

See [PRIVACY.md](PRIVACY.md), [SAFETY_MODEL.md](SAFETY_MODEL.md), and [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for the detailed guarantees and limitations.

## Recovery and support

- Items moved to Trash can be restored through Finder before Trash is emptied.
- Vault-backed operations are recorded locally and can be restored without overwriting an existing destination.
- When reporting a problem, include the ByteTrail version, macOS version, exact warning text, and whether the SHA-256 verification passed. Do not publish private file paths or personal scan results in a public issue.

Development and build instructions are in [DEVELOPMENT.md](DEVELOPMENT.md). Release verification details are in [outputs/BUILD_NOTES.md](outputs/BUILD_NOTES.md).

---

## 中文使用说明

ByteTrail 是一款完全本地运行的 macOS 磁盘空间分析与清理工具。它不会联网，不会上传文件路径、应用列表或扫描结果，也不包含遥测、广告、云端分类或 AI 模型。

### 下载与安装

1. 从 [GitHub Releases](https://github.com/LeMat11/ByteTrail/releases/latest) 下载 `ByteTrail.dmg` 和 `SHA256.txt`。
2. 如需校验，在终端进入下载目录并运行 `shasum -a 256 -c SHA256.txt`；看到 `ByteTrail.dmg: OK` 后再继续。
3. 打开 DMG，把 ByteTrail 拖入“应用程序”文件夹。
4. 在 Finder → 应用程序中启动 ByteTrail。

### macOS 阻止首次打开时

ByteTrail 1.2 尚未取得 Apple Developer ID 签名和公证，因此 macOS 可能阻止第一次启动。请先确认安装包来自本项目官方 GitHub Release，并且 SHA-256 校验一致，然后：

1. 尝试打开 ByteTrail 一次并关闭系统警告。
2. 打开 **苹果菜单 → 系统设置 → 隐私与安全性**。
3. 向下找到“安全性”区域，点击 ByteTrail 旁边的 **仍要打开**。
4. 使用登录密码或 Touch ID 验证，再确认打开。

“仍要打开”通常只会在首次启动被阻止后显示约一小时。部分 macOS 版本也可以在 Finder 中按住 Control 点击 ByteTrail，选择“打开”，然后再次确认。

请不要关闭整个系统的 Gatekeeper，不要降低全局安全设置，也不要运行 `sudo` 或删除 quarantine 属性的绕过命令。如果系统提示 App 已损坏，请重新从官方 Release 下载并再次核对 SHA-256；校验不一致时不要继续打开。

### 扫描与清理

1. 启动扫描；扫描只读取和分析，不会自动修改文件。
2. 查看每个结果的来源、路径、大小、可信度、风险和清理说明。
3. 只勾选你确认需要处理的项目。
4. 点击 **Clean Up Selected / 清理已选项目**。

Release 版能够执行真实清理，但不会永久删除文件。符合条件的项目通常会移入废纸篓，部分普通项目可能进入 ByteTrail 的可恢复保险库。ByteTrail 不会自动清空废纸篓；需要你自行清空废纸篓后，相应空间才会真正释放。

系统应用、ByteTrail 自身、正在运行的应用、受保护的个人数据、路径校验失败或扫描后发生变化的目标都会被拒绝处理。卸载残留只是保守建议，始终需要人工 Review，不会自动勾选。

如果通过 Xcode 直接 Run，默认得到的是 Debug 版本：它默认 Dry Run，并且开发安全锁不允许修改真实用户路径。要体验实际清理，请使用 GitHub Release 中的安装版本。
