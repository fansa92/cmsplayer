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
| 分类浏览 | 分类导航（支持多选分类）+ 年代 / 地区 / 排序字段与升降序 + 首字母 A–Z 侧栏 + 「已完结」开关 + 分页 |
| 首页 | 今日热播 / 本月热门 / 高分佳作三个横排板块，下接最近更新网格；板块取不到数据就不显示 |
| 榜单 | 按最多播放 / 最高评分 / 最新更新看当前资源站的头几名（顶栏榜单图标进入） |
| 搜索 | 单源搜索；多源并发搜索并按「片名 + 年代」聚合，同一部片只显示一条并标注命中几个源；打字时给出联想词（去抖 + 缓存，接口不支持自动降级）；手动触发正式搜索（回车或「搜索」按钮） |
| 详情页 | 多线路切换、多选集、评分 / 片长 / 播放量 / 完结状态、导演 / 演员可点开找同人作品、分类可点进分类浏览、底部相似推荐、收藏、续播入口；有记录时自动切到上次的线路并滚到那一集 |
| 播放器 | 手势音量 / 亮度 / 进度、倍速、选集、画幅切换、锁屏、自动下一集、音轨切换、字幕（内嵌轨切换 + 外挂 SRT / ASS）、定时关闭 |
| 手动换源 | 播放器里直接到其它已启用资源站找同一部片子的同一集，片名 / 年代 / 集名对不上就不列 |
| 片头片尾 | 按片名记住片头结束 / 片尾开始（换源、清空历史后仍然生效），开播自动跳过片头、播到片尾直接进下一集（可关） |
| 桌面播放 | 窗口全屏、迷你悬浮窗（置顶 · 420×236）、鼠标移动唤出控制栏、空格 / 方向键 / F 快捷键 |
| 记忆播放 | 按「源 + 影片 + 线路 + 集数」记住进度，下次进来自动跳转 |
| 收藏 / 历史 | 本地 JSON 持久化，支持按源筛选、滑动删除、清空；收藏会按源批量比对集数，有新集时打「更新至 N 集」角标并可筛选；「追剧更新」页按新增集数排开所有更新、可一键全部已读；历史可长按进入多选批量删除 |
| 备份导出 | 播放记录 / 收藏 / 源 / 搜索词 / 设置一键导出成单个 JSON 文件（不含任何凭据） |
| 更新检查 | 设置页比对 GitHub 最新发行版，有新版时给出版本说明与下载链接（一键复制） |
| 接口兼容 | JSON（v10 字典 / 老数组）与老版 XML 采集格式都认；GBK 自动解码；按 ID 取详情时 `ac=detail` 拿不到播放地址会自动试 `ac=videolist` 并记住该源的偏好；源站的 `code/msg` 错误直接透出，不会显示成「暂无数据」 |
| 主题 | Material 3，跟随系统 / 浅色 / 深色 |

### 播放器手势

| 手势 | 作用 |
| --- | --- |
| 单击 | 显示 / 隐藏控制栏 |
| 双击中间 | 播放 / 暂停 |
| 双击左侧 / 右侧 | 快退 / 快进 10 秒 |
| 长按画面 | 临时 2 倍速，松手恢复 |
| 左右拖动 | 拖动进度（松手后跳转） |
| 屏幕左半区上下拖动 | 调节亮度 |
| 屏幕右半区上下拖动 | 调节音量 |
| 顶栏锁形按钮 | 锁屏：以上手势全部失效，画面中央只剩解锁按钮 |
| 顶栏横屏按钮 | 强制横屏播放 / 切回竖屏（仅移动端，退出播放页自动恢复） |

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

### 主界面快捷键

| 按键 | 作用 |
| --- | --- |
| `Ctrl/⌘ + F`、`/` | 跳到搜索页并聚焦输入框 |
| `Ctrl/⌘ + 1` ~ `5` | 切换到第 N 个页签（首页 / 分类 / 搜索 / 收藏 / 历史） |
| `Esc` | 返回上一层；已在最外层时收起输入焦点 |
| `?` | 弹出快捷键说明（桌面端顶栏也有一个键盘图标） |

在输入框里打字时 `/` 与 `?` 不会被当成快捷键。

---

## 二、快速开始

```bash
# 1. 依赖
flutter pub get

# 2. 静态检查（应输出 "No issues found!"）
dart analyze

# 3. 单元测试（覆盖接口解析 / 播放地址三级结构 / 源规范化 / 在线导入宽容解析 /
#    分类分层 / 模型 JSON 往返 / 编码识别 / 播放降级与跨源降级 / 同步合并与墓碑 /
#    工具函数 / 响应式断点 / 继续观看横条 / WebDAV 与局域网传输 / 同步编排 /
#    历史·收藏·资源站·同步·浏览·搜索状态 / 页签懒挂载 / 图片缓存 LRU /
#    海报骨架屏与卡片语义 / 无限滚动去重 / 主题与窄屏布局 /
#    详情页选集虚拟滚动 / 详情页续播定位 / 快捷键映射 / 深浅主题对比度 /
#    播放器外观与弹层 / 播放器键盘·手势·自动隐藏 / 观看记录多选删除 /
#    榜单状态与页面 / 手动换源 / 更新检查与版本比对 / 备份包往返与写盘 /
#    播放状态机（地址解析 / 流绑定 / 续播 / 自动下一集 / 记录节流 / 降级链 / 重试 /
#    音轨切换 / 定时关闭 / 片头片尾跳过 / 长按临时倍速 /
#    分类多选与已完结筛选 / 搜索跨源聚合 / 首页板块)
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

> **本仓库当前状态**：`dart analyze` 全绿、`flutter test` 全部通过、
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
| `ac` | `list` / `detail` / `videolist` | 精简列表 / 详情（含播放地址）/ 老采集接口的全字段模式 |
| `at` | `json` | 显式声明要 JSON；老站仍返回 XML 时走另一套解析 |
| `t` | `int` 或 `6,7` | 分类 ID，`0`（不传）为全部；逗号形式是分类多选 |
| `pg` | `int` | 页码，从 1 开始 |
| `pagesize` / `limit` | `int` | 每页条数（两个都发，兼容不同版本） |
| `wd` | `String` | 搜索关键词 |
| `ids` | `1,2,3` | 影片 ID，批量详情 / 收藏更新检查 |
| `h` / `m` | `int` | 最近 N 小时 / 本月热播（首页用 `h=24`、`m=30`） |
| `year` / `area` / `lang` | `String` | 年代 / 地区 / 语言筛选 |
| `by` / `order` | `String` | 排序字段（`time`、`hits`、`score`）/ 方向（`asc`、`desc`） |
| `letter` | `A`–`Z` | 片名首字母，配合 A–Z 侧栏 |
| `isend` | `1` / `0` | 已完结筛选；非标准参数，服务端不认时本地再筛一遍 |

**兼容性说明**：

- 按 ID 取详情时，若 `ac=detail` 请求失败或返回条目却没有 `vod_play_url`，会自动重试
  `ac=videolist`，成功后按源记住偏好，后续不再多打一次请求；列表查询不做这个降级。
- 响应解析同时认三种结构：v10 的 `{code,msg,page,list,class}`、老版本顶层数组，
  以及 v8 采集接口的 RSS/XML（`<list><video><dl><dd from=…>` 那套字段）。
- 顶层 `code <= 0` 且没有数据时，把 `msg` 作为错误抛出，不会当成空列表。
- 搜索联想词走 `/api.php/vod/suggest` 与 `/index.php/ajax/suggest`（返回结构按字段容错解析），
  两个都不可用时静默退回 `ac=list&wd=` 拿前几部片名。
- 还没接的站点可选参数：`from`（播放源筛选）、路径式 `/from/xxx/`、`state` / `level` /
  `tag` / `class` / `version` / `actor` / `director` 等 `typefilter` 扩展，以及自定义时间窗。

播放地址按 `vod_play_from` / `vod_play_url` 的三级结构解析：

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
│   ├── storage/                  AppDirs / JsonStore / SettingsStore / ShowMarksStore（按片名记片头片尾）
│   └── utils/                    HTML 剥离、实体解码、时长格式化、响应式断点、防抖
├── data/
│   ├── api/maccms_api.dart       接口客户端 + JSON 响应解析 + 联想词（核心）
│   ├── api/xml_vod_parser.dart   老版 RSS/XML 采集格式解析
│   ├── api/source_importer.dart  源批量导入
│   ├── models/                   VodSource / VodItem / PlayLine / PlayRecord / FavoriteItem…
│   └── repository/               Vod / Source / Record 三个仓库
├── state/                        ChangeNotifier：Browse / Home / Search / Favorites / History / Source / Rank / App
└── ui/
    ├── pages/                    首页 / 分类 / 搜索 / 收藏 / 追剧更新 / 历史 / 详情 / 关键词结果 / 榜单 / 源管理 / 设置
    ├── player/                   手势与底栏 player_controls / 外观 player_chrome /
    │                             弹层 player_sheets / PlayerController + PlayerPage / 全屏与迷你窗 player_window
    ├── widgets/                  CachedImage / VodCard / VodGrid / PosterSkeleton / OptionPicker
    ├── shell/                    app_shell 自适应导航 + app_shortcuts 全局快捷键
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
- 支持 **UTF-8 / GBK / GB2312 / Big5**：先按源里配置的字符集与响应头 `Content-Type`
  解码，再严格尝试 UTF-8，最后用 GBK 兜底。老站仍乱码时可在源的高级选项里
  显式指定字符集。

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
| 详情页提示「该资源站没有返回播放地址」 | `vod_play_url` 为空，换线路或换源；老站会自动再试一次 `ac=videolist` |
| 「测试」按钮报「响应不是合法 JSON 或 macCMS XML」 | 接口返回的是 HTML 错误页（CDN 拦截 / 需要代理 / 地址失效），不是数据接口 |
| 筛选里没有 A–Z 侧栏 | 该源没返回 `vod_letter`，片名也不以英文字母开头；侧栏只在有可用字母时出现 |
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
git tag v1.0.4
git push origin v1.0.4
```

版本号取自标签（去掉 `v`）；手动触发时用 `pubspec.yaml` 的版本 + 短 commit，
产物名即 `CMSPlayer-1.0.4-dev.abc1234-…`。

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
