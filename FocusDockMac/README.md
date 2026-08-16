# FocusDock for macOS

原生 SwiftUI 番茄钟、节律提醒和桌面宠物参考实现。

## 需要的环境

- macOS 14+
- Xcode Command Line Tools
- Swift 6

## 运行测试

```bash
swift test
```

## 构建应用包

```bash
Scripts/build-app.sh
open dist/FocusDock.app
```

生成的应用位于 `dist/FocusDock.app`。本地脚本使用 Ad Hoc 签名，目的是开发和测试，不是面向普通用户的正式分发。

如需站外分发，请另行配置 Apple Developer ID、Hardened Runtime、公证和对应架构的构建。Windows 不能直接运行这份 SwiftUI 应用。
