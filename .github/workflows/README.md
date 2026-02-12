# GitHub Actions 工作流说明

本项目包含多个 GitHub Actions 工作流，用于自动化构建和发布。

## 工作流文件

### 1. `build-windows.yml` - Windows 构建
- **触发条件**：推送到 main/master 分支、PR、手动触发
- **构建平台**：Windows amd64
- **输出**：Windows 安装程序 (.exe)

### 2. `build-all-platforms.yml` - 全平台构建
- **触发条件**：推送到 main/master 分支、PR、手动触发
- **构建平台**：
  - Windows: amd64
  - macOS: amd64, arm64
  - Linux: amd64, arm64
  - Android: arm64-v8a, armeabi-v7a, x86_64
  - iOS: universal
- **输出**：所有平台的安装包
- **特点**：完整的多平台构建，适合测试

### 3. `build-release.yml` - 发布构建
- **触发条件**：推送 tag (v*)、手动触发
- **构建平台**：
  - Windows: amd64
  - macOS: amd64, arm64
  - Linux: amd64, arm64
  - Android: arm64-v8a, armeabi-v7a
- **输出**：所有平台的发布包
- **特点**：
  - 自动创建 GitHub Release
  - 上传所有构建产物
  - 生成发布说明

## 使用方法

### 手动触发构建

1. 进入 GitHub 仓库的 Actions 页面
2. 选择要运行的工作流
3. 点击 "Run workflow" 按钮
4. 选择分支并运行

### 创建发布版本

1. 创建并推送 tag：
   ```bash
   git tag v0.8.91
   git push origin v0.8.91
   ```

2. GitHub Actions 会自动：
   - 构建所有平台
   - 创建 GitHub Release
   - 上传所有安装包

### 查看构建产物

1. 进入 Actions 页面
2. 点击具体的工作流运行
3. 在 "Artifacts" 部分下载构建产物

## 构建架构说明

### Windows
- **amd64**: 64位 Intel/AMD 处理器（主流）
- **证书要求**: ❌ 不需要（未签名可用，安装时会有警告）

### macOS
- **amd64**: Intel 芯片的 Mac
- **arm64**: Apple Silicon (M1/M2/M3) 芯片的 Mac
- **证书要求**: ⚠️ 建议签名（未签名需手动允许运行）

### Linux
- **amd64**: 64位 Intel/AMD 处理器
- **arm64**: ARM64 架构（如树莓派 4）
- **证书要求**: ❌ 不需要

### Android
- **arm64-v8a**: 64位 ARM 设备（主流现代手机）
- **armeabi-v7a**: 32位 ARM 设备（旧手机）
- **x86_64**: x86 架构（模拟器）
- **证书要求**: ❌ 不需要（调试版 APK）

### iOS
- **不支持**: 需要 Apple 开发者账号（$99/年）和签名证书
- **原因**: 
  - iOS 必须签名才能安装
  - 无法在 GitHub Actions 上自动构建
  - 用户也无法自己编译安装
- **如需 iOS 版本**: 请自行购买开发者账号并本地编译
- **arm64**: Apple Silicon (M1/M2/M3) 芯片的 Mac

### Linux
- **amd64**: 64位 Intel/AMD 处理器
- **arm64**: ARM64 架构（如树莓派 4）

### Android
- **arm64-v8a**: 64位 ARM 设备（主流现代手机）
- **armeabi-v7a**: 32位 ARM 设备（旧手机）
- **x86_64**: x86 架构（模拟器）

## 构建时间估计

- Windows: ~15-20 分钟
- macOS: ~20-25 分钟（每个架构）
- Linux: ~15-20 分钟（每个架构）
- Android: ~20-25 分钟（每个架构）

全平台构建总时间：约 1.5-2 小时（并行执行）

## 依赖项

所有工作流都会自动安装以下依赖：

- Flutter (beta 频道)
- Dart
- Go 1.23
- Rust (stable)
- 平台特定工具：
  - Windows: Inno Setup
  - macOS: create-dmg
  - Linux: GTK3, CMake, Ninja
  - Android: Java 17, Android NDK r26d

## 故障排查

### 构建失败

1. 检查 Actions 日志中的错误信息
2. 常见问题：
   - 依赖安装失败：重新运行工作流
   - 子模块未初始化：确保 `submodules: recursive`
   - 权限问题：检查 GITHUB_TOKEN 权限

### 产物缺失

1. 确认构建步骤成功完成
2. 检查 `dist` 目录是否生成
3. 验证 `upload-artifact` 步骤的路径配置

### Release 创建失败

1. 确保推送了正确格式的 tag (v*)
2. 检查 GITHUB_TOKEN 是否有创建 Release 的权限
3. 验证所有构建任务都成功完成

## 自定义配置

### 修改构建架构

编辑工作流文件中的 `strategy.matrix.arch` 部分：

```yaml
strategy:
  matrix:
    arch: [amd64, arm64]  # 添加或删除架构
```

### 修改 Flutter 频道

修改 `flutter-action` 的 `channel` 参数：

```yaml
- name: Setup Flutter
  uses: subosito/flutter-action@v2
  with:
    channel: 'stable'  # 可选: stable, beta, dev
```

### 添加签名

对于生产环境，建议添加代码签名：

1. 将签名证书添加到 GitHub Secrets
2. 在构建步骤前添加签名配置
3. 修改构建命令包含签名参数

## 注意事项

1. **构建时间**：全平台构建需要较长时间，建议只在发布时使用
2. **存储空间**：产物会占用 GitHub Actions 存储空间
3. **并发限制**：免费账户有并发任务限制
4. **私有仓库**：私有仓库的 Actions 分钟数有限制

## 推荐工作流

### 日常开发
使用 `build-windows.yml` 进行快速测试

### 测试发布
使用 `build-all-platforms.yml` 验证所有平台

### 正式发布
使用 `build-release.yml` 创建发布版本
