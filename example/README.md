# Flutter TTS Engine Example

这是一个展示如何使用 Flutter TTS Engine 包的示例应用。

## 功能特点

- 支持多个 TTS 引擎（Edge TTS 和 Azure TTS）
- 提供多种声音选项
- 实时文本转语音转换
- 简洁的用户界面

## 运行示例

1. 确保你已经安装了 Flutter SDK
2. 克隆这个仓库
3. 进入 example 目录
4. 运行以下命令：

```bash
flutter pub get
flutter run
```

## 使用说明

1. 从下拉菜单中选择 TTS 引擎（Edge TTS 或 Azure TTS）
2. 选择想要的声音类型
3. 在文本框中输入要转换的文字
4. 点击"转换为语音"按钮
5. 等待转换完成

## 注意事项

- 示例中使用的是免费的 TTS 服务，可能会有一些限制
- 在实际应用中，你可能需要添加错误处理和重试机制
- 建议在使用 Azure TTS 时添加自己的 API 密钥 