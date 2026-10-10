# CMSPlayer

一个 **macCMS（苹果CMS）VOD 接口播放器**，对标 Apple App Store 上的 CMSPlayer。

应用本身 **不内置、不提供、不分发任何影片内容** —— 它只是一个对接资源站接口的客户端：
你添加资源站地址，它负责拉分类、搜索、取详情与播放线路，再交给 libmpv 解码播放。

技术栈：**Flutter + media_kit（libmpv）+ provider**，单套代码跑 **Windows / macOS / Linux / Android / iOS** 五端，
零代码生成（不用 Hive / Isar / sqflite / build_runner）。

---

## 一、功能

| 模块 | 说明 |
| --- | --- |
| 多源管理 | 添加 / 编辑 / 删除 / 拖拽排序 / 启停 / 单个与批量并发测速 |
| 批量导入 | 从 URL 导入官方源列表、粘贴 JSON 导入、一键导出 JSON |
| 分类浏览 | 分类导航 + 年代 / 地区 / 排序三维筛选 + 分页 |
| 搜索 | 单源搜索；多源并发搜索并合并去重，结果卡片标注来源 |
| 详情页 | 多线路切换、多选集、导演 / 演员 / 简介、收藏、续播入口 |
| 播放器 | 手势音量 / 亮度 / 进度、倍速、选集、画幅切换、锁屏、自动下一集 |
| 桌面播放 | 窗口全屏、鼠标移动唤出控制栏、空格 / 方向键 / F 快捷键 |
| 记忆播放 | 按「源 + 影片 + 线路 + 集数」记住进度，下次进来自动跳转 |
| 收藏 / 历史 | 本地 JSON 持久化，支持按源筛选、滑动删除、清空 |
| 主题 | Material 3，跟随系统 / 浅色 / 深色 |

### 播放器手势

| 手势 | 作用 |
| --- | --- |
| 单击 | 显示 / 隐藏控制栏 |
| 双击 | 播放 / 暂停 |
| 左右拖动 | 拖动进度（松手后跳转） |
| 屏幕左半区上下拖动 | 调节亮度 |
| 屏幕右半区上下拖动 | 调节音量 |
| 顶栏锁形按钮 | 锁屏：以上手势全部失效，画面中央只剩解锁按钮 |

### 桌面快捷键

| 按键 | 作用 |
| --- | --- |
| `空格` / `K` | 播放 / 暂停 |
| `←` / `J` | 快退 10 秒 |
| `→` / `L` | 快进 10 秒 |
| `↑` / `↓` | 音量 ±5% |
| `F` | 窗口全屏切换 |
| `Esc` | 退出全屏；再次按下退出播放 |

鼠标在画面上移动即可唤出控制栏，停止移动 4 秒后自动隐藏。锁屏按钮桌面与
移动端都有；全屏按钮只在桌面出现（移动端进入播放页即为系统级沉浸式全屏）。

---

## 二、快速开始

```bash
# 1. 依赖
flutter pub get

# 2. 静态检查（应输出 "No issues found!"）
dart analyze

# 3. 单元测试（21 个用例，覆盖接口解析 / 播放地址三级结构 / 源规范化 /
#    在线导入宽容解析 / 分类分层）
flutter test

# 4. 生成平台目录（本仓库已包含，重新生成时用）
flutter create --project-name cms_player --org com.cmsplayer \
  --platforms=windows,macos,linux,android,ios .
```

### 各平台构建

| 平台 | 前置条件 | 命令 |
| --- | --- | --- |
| Windows | Visual Studio 2022，勾选 **使用 C++ 的桌面开发**（含 MSVC 与 Windows SDK） | `flutter build windows --release` |
| macOS | macOS + Xcode 16 | `flutter build macos --release` |
| iOS | macOS + Xcode 16（真机需开发者账号签名） | `flutter build ios --release --no-codesign` |
| Linux | `clang cmake ninja-build pkg-config libgtk-3-dev` | `flutter build linux --release` |
| Android | Android Studio + SDK（含 NDK，media_kit 需要） | `flutter build apk --release` |

运行调试用 `flutter run -d windows` / `-d macos` / `-d chrome`（Web 端 media_kit 支持有限，仅作 UI 预览）。

> **本仓库当前状态**：`dart analyze` 全绿、`flutter test` 13/13 通过、
> `flutter build bundle --target-platform=windows-x64` 编译成功。
> 原生链接（CMake / MSVC）尚未在本机执行 —— 开发机未安装 Visual Studio，
> 装好 VS 后直接 `flutter build windows --release` 即可出 exe，
> 或推一个 `v*` 标签让 GitHub Actions 一次跑完五个平台（见下文「八、CI 与自动发布」）。

---

## 三、配置资源站

应用启动时若没有任何源，会直接进入「资源站管理」页。

### 1. 源格式

官方源列表是 JSON 数组，元素为 `name` + `api`（+ 可选 `note`）：

```json
[
  {
    "name": "示例资源站",
    "api": "https://example.com/api.php/provide/vod/",
    "note": "每日更新",
    "referer": "https://example.com/",
    "userAgent": "",
    "parseApi": "https://jx.example.com/?url="
  }
]
```

`api` 会被自动规范化（补上结尾的 `/`）；`name` 留空时自动取主机名。
源的 `id` 由 `name|api` 哈希生成，因此**重复导入不会产生重复项**。

只有 `name` / `api` / `note` 是官方格式字段，其余都是可选扩展：
- `referer`：不填则用接口地址的源站
- `userAgent`：部分站点校验 UA
- `parseApi`：播放地址不是直链时的解析前缀，`{url}` 会被替换为 `encodeURIComponent(地址)`

### 2. 官方源列表

在「资源站管理」页点右上角的 **🔗 从 URL 导入**，默认值为：

```
https://raw.githubusercontent.com/cms-player/vod-source/main/source.json
```

国内打不开时改用镜像：

```
https://mirror.ghproxy.com/https://raw.githubusercontent.com/cms-player/vod-source/main/source.json
```

也可以 **📋 粘贴 JSON 导入**，或点 **⋯ → 导出为 JSON** 分享当前配置。

---

## 四、对接的接口协议

只用 macCMS 的标准参数，因此任何苹果CMS 系资源站都能直接接：

| 参数 | 取值 | 用途 |
| --- | --- | --- |
| `ac` | `list` / `detail` | 列表模式 / 详情模式（取播放地址必须 `detail`） |
| `t` | `int` | 分类 ID，`0` 为全部 |
| `pg` | `int` | 页码，从 1 开始 |
| `pagesize` | `int` | 每页条数 |
| `wd` | `String` | 搜索关键词 |
| `ids` | `int` | 影片 ID（详情） |
| `h` / `m` | `int` | 时长上下限（小时 / 分钟） |
| `area` / `lang` / `year` / `by` | `String` | 地区 / 语言 / 年份 / 排序（`time`、`hits`、`score`） |

响应同时兼容 v10 字典结构与老版本数组结构；`vod_play_from` 与 `vod_play_url` 按下面三级结构解析：

```
线路1名字$$$线路2名字
    ↓
第01集$地址1#第02集$地址2$$$第01集$地址3
    ↓
单集名$主地址$备用地址$备用地址2
```

接口返回的 `pagecount` 缺失时，按 `ceil(total / limit)` 推算。

---

## 五、目录结构

```
lib/
├── main.dart / app.dart          入口与依赖注入（MultiProvider）
├── core/
│   ├── constants.dart            全部常量、内置示例源、官方源列表地址
│   ├── theme/app_theme.dart      Material 3 主题
│   ├── storage/                  AppDirs / JsonStore / SettingsStore
│   └── utils/                    HTML 剥离、实体解码、时长格式化、响应式断点、防抖
├── data/
│   ├── api/maccms_api.dart       接口客户端 + 响应解析（核心）
│   ├── api/source_importer.dart  源批量导入
│   ├── models/                   VodSource / VodItem / PlayLine / PlayRecord / FavoriteItem…
│   └── repository/               Vod / Source / Record 三个仓库
├── state/                        ChangeNotifier：Browse / Search / Favorites / History / Source / App
└── ui/
    ├── pages/                    首页 / 分类 / 搜索 / 收藏 / 历史 / 详情 / 源管理 / 设置
    ├── player/                   PlayerController + PlayerPage + PlayerControls
    ├── widgets/                  CachedImage / VodCard / VodGrid / EmptyState / OptionPicker
    ├── shell/app_shell.dart      自适应导航（窄屏底部栏，宽屏侧边栏）
    └── navigation.dart           统一跳转入口
```

**图片缓存**没有用 `cached_network_image`，而是 `ui/widgets/cached_image.dart` 里 40 行的
内存 + 磁盘两级缓存，方便在桌面端控制行为，避免额外依赖。

---

## 六、平台注意事项

### Android
- 源地址若是 `http://`（明文），必须在 `android/app/src/main/AndroidManifest.xml` 里开 cleartext：
  ```xml
  <application android:usesCleartextTraffic="true" ...>
  ```
- 部分 ROM 对音量 / 亮度插件有权限限制，失败时手势会静默降级（不闪退）。

### iOS / macOS
- `http://` 明文地址需要 ATS 例外，在 `ios/Runner/Info.plist`（或 macOS 对应文件）加：
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  ```
- iOS 真机与上架需要在 Xcode 里配好签名（Bundle ID 默认 `com.cmsplayer.cmsPlayer`）。
- `screen_brightness` / `volume_controller` 在 iOS 上需要真机，模拟器行为可能不同。

### 编码
- 仅支持 **UTF-8** 源。部分老资源站返回 GBK/GB2312，会解析失败并提示
  「接口返回的不是数据」。这类源需要服务端转码，或加一层反代。

### 网络
- 需要代理的源（如 GitHub 源列表），请先在系统层配好代理，应用内直接走系统代理。
- 部分站点校验 `Referer` / `UA`，在源的「高级选项」里填即可。
- 播放地址跨域或需要带请求头时，`VodSource.headers` 会作为 `Media` 的
  `httpHeaders` 一并传给 libmpv。

### 桌面
- media_kit 首次构建会下载对应平台的 libmpv 动态库（`media_kit_libs_video`）。
- Windows 若报 `Unable to find suitable Visual Studio toolchain`，装 VS 时务必勾选
  **使用 C++ 的桌面开发** 工作负载。

---

## 七、常见问题

| 现象 | 原因与处理 |
| --- | --- |
| 「测试」按钮一直失败 | 接口地址写错，或站点有 CDN 防护。确认浏览器能打开 `接口地址?ac=list` |
| 分类有、但点进去没有剧集 | 列表接口要开 `ac=detail`，或该源只在搜索时返回地址 |
| 详情页提示「该资源站没有返回播放地址」 | `vod_play_url` 为空，换线路或换源 |
| 播放失败 / 黑屏 | 地址不是直链。在源里填 `parseApi`，或确认地址能直接在浏览器播放 |
| 只有声音没画面 | 关掉设置里的「硬件解码」改用软解 |
| 进度不记忆 | 该集时长小于 `K.minResumeSource` 时不会写入；或进度超过 90% 被判定为已看完 |
| 拖拽排序后顺序不对 | 已用 `onReorderItem`（新语义），与 `SourceStore.move` 的直接 `removeAt/insert` 一致 |

---

## 八、CI 与自动发布

`.github/workflows/build.yml` 会在 **推送 `v*` 标签** 或 **手动触发** 时跑全平台构建。

### 流程

```
quality（dart analyze + flutter test）
   └─> meta（解析版本号）
         ├─> android  ─┐
         ├─> windows   │  五个平台并行
         ├─> macos     │
         ├─> linux     │
         └─> ios      ─┘
                        └─> release（仅 v* 标签时创建 GitHub Release）
```

任一阶段失败，后面的构建不会启动。

### 产物

| 平台 | 文件 | 签名 |
| --- | --- | --- |
| Windows | `CMSPlayer-<v>-windows-x64.zip` | 不签名 |
| Android | `CMSPlayer-<v>-android.apks`（bundletool，`--mode=universal`，含全部 ABI）<br>`CMSPlayer-<v>-android-universal.apk`（从 .apks 解出，方便手动安装）<br>`CMSPlayer-<v>-android-abi-splits/` 下 `armeabi-v7a` / `arm64-v8a` / `x86_64` 三个 APK | **自签** |
| macOS | `CMSPlayer-<v>-macos-universal.dmg` | ad-hoc（`CODE_SIGN_IDENTITY = "-"`），无 Apple 开发者证书、未公证 |
| Linux | `CMSPlayer-<v>-linux-x64-portable.tar.gz` | 不签名 |
| iOS | `CMSPlayer-<v>-ios-unsigned.ipa`（`--no-codesign`） | 不签名 |

### 发布

```bash
git tag v1.0.0
git push origin v1.0.0
```

版本号取自标签（去掉 `v`）；手动触发时用 `pubspec.yaml` 的版本 + 短 commit，
产物名即 `CMSPlayer-1.0.0-dev.abc1234-…`。

### 可选 Secrets

只有 Android 需要。**不配也能跑** —— CI 会在每次运行时现签一个新密钥。

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_B64` | keystore 文件的 base64（PKCS12 格式，`.p12` / `.jks` 均可）。配置后签名跨版本一致，可覆盖安装 |
| `ANDROID_KEYSTORE_PASSWORD` | 不配则用 `cmsplayer-ci` |
| `ANDROID_KEY_ALIAS` | 不配则用 `cmsplayer` |
| `ANDROID_KEY_PASSWORD` | 不配则同 storePassword |

> **重要**：每次运行现签一个新密钥意味着 **不同构建之间签名不一致，无法覆盖安装**。
> 真要对外分发 Android，请务必把 keystore 存进 Secret。

#### 生成 keystore

机器上有 JDK 就用 `keytool`，没有就用 `openssl`（Git for Windows 自带）：

```bash
# 方式一：keytool（JDK 9+ 默认输出就是 PKCS12）
keytool -genkeypair -v -keystore release.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias cmsplayer \
  -storepass <密码> -keypass <密码> \
  -dname "CN=CMSPlayer, OU=Self-Signed, O=CMSPlayer, L=NA, ST=NA, C=US"

# 方式二：openssl（不用装 JDK）
openssl req -x509 -newkey rsa:2048 -sha256 -days 10000 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/CN=CMSPlayer/OU=Self-Signed/O=CMSPlayer/L=NA/ST=NA/C=US"
openssl pkcs12 -export -inkey key.pem -in cert.pem \
  -out release.p12 -name cmsplayer -passout pass:<密码>
```

然后编码成一行存进 Secret：

```bash
base64 -w0 release.p12                              # Linux
# base64 -i release.p12 | tr -d '\n'                # macOS
# [Convert]::ToBase64String([IO.File]::ReadAllBytes("release.p12"))   # PowerShell
```

> **格式**：CI 会把 `storeType=PKCS12` 显式写进 `key.properties`，不依赖 AGP 的默认猜测。
> JDK 9 起 keytool 与 openssl 的默认输出都是 PKCS12，所以两条路都不用额外设置。
> 手上有真正的 JKS 文件时，在 `key.properties` 里加 `storeType=JKS` 即可
> （`build.gradle.kts` 已支持读取该字段）。
>
> **openssl 3.x 的坑**：它默认用 `PBES2/PBKDF2/AES-256-CBC` + `hmacWithSHA256`，
> JDK 17（CI 所用）能正常读取；但 8u301 / 11.0.1 之前的老 JDK 不认。
> 需要兼容老 JDK 时加 `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`。

**别忘了把 keystore 文件妥善备份** —— 它是后续更新 App 的唯一凭证，丢了以后发的版本
将无法覆盖安装。

手动触发 workflow 时可勾选 `skip_apple` 跳过 macOS / iOS
（macOS runner 按 10 倍分钟计费，只想验证 Windows/Android 时很划算）。

### 几个坑（已在 workflow 里处理）

- **Runner 版本必须显式钉住**：`ubuntu-latest` 自 2026-10 起切到 26.04，
  而 `ubuntu-22.04` 已于 2026-09-17 开始弃用。因此原生构建固定用 `ubuntu-24.04`。
- **Android 是 Kotlin DSL**：`build.gradle.kts` 已改为读取 `android/key.properties`，
  没有该文件时自动回退到 debug 密钥，本地 `flutter run --release` 不受影响。
  `key.properties` / `*.jks` 已加入 `.gitignore`。
- **macOS 无需证书**：模板里三套构建配置的 `CODE_SIGN_IDENTITY` 本就是 `-`，
  CI 直接 `flutter build macos` 即可，产出 ad-hoc 签名的应用。
- **iOS 不签名**：`--no-codesign` 后直接把 `Runner.app` 塞进 `Payload/` 打成 ipa，
  下载后需自行用描述文件重签才能安装。

### Linux 免依赖包的边界

`.github/scripts/bundle-linux.sh` 用 `ldd` 递归收集 GTK / Cairo / Pango 等约 60 个
系统库到 `bundle/lib/`，再用 `patchelf` 把所有 ELF 的 RPATH 改写成
`$ORIGIN:$ORIGIN/lib`（RUNPATH 不会传递给子进程，所以每个 `.so` 都必须自带），
最后校验 `ldd` 无 `not found`。

**能免掉的**：libgtk-3、libcairo、libpango、libgdk-pixbuf、libstdc++ 等
用户态依赖，解压即用。

**免不掉的**：`glibc` 与 `ld-linux`（打进去必段错误），所以要求目标机器
glibc ≥ 构建镜像的版本，即 **glibc ≥ 2.39（Ubuntu 24.04 / Debian 13 / Fedora 41+）**。

需要支持更老的发行版（如 Ubuntu 22.04），把 `linux` job 的 `runs-on`
换成容器即可：

```yaml
    runs-on: ubuntu-24.04
    container: ubuntu:22.04      # glibc 2.35，兼容面大得多
    steps:
      - name: 先装 git（否则 checkout 拿不到 .git）
        run: apt-get update && apt-get install -y git curl ca-certificates
      - uses: actions/checkout@v5
      # ……其余步骤同上，apt-get 前加 sudo apt-get 或直接 apt-get
```

---

## 九、免责

本应用为通用的接口播放客户端，不内置、不提供、不分发任何影片内容，
所有内容均由用户自行添加的资源站提供。请仅用于播放你有权访问的内容。
