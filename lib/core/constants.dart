/// 全局常量。
class K {
  K._();

  static const String appName = 'CMSPlayer';
  static const String appNameCn = 'CMS 播放器';
  static const String appVersion = '1.0.0';

  // ---------------- 网络 ----------------
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 20);

  /// 列表默认每页条数。
  static const int defaultPageSize = 20;

  /// 通用浏览器 UA。部分资源站会拒绝非浏览器请求。
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // ---------------- 缓存 ----------------
  /// 列表 / 分类内存缓存有效期。
  static const Duration listCacheTtl = Duration(minutes: 10);
  static const int maxCacheEntries = 120;

  // ---------------- 播放 ----------------
  static const List<double> playRates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

  /// 少于该时长不写入续播进度，避免"秒进秒出"污染记录。
  static const Duration minResumeSource = Duration(seconds: 20);

  /// 播放进度达到总时长的该比例即视为"已看完"。
  static const double finishRatio = 0.95;

  /// 进度落后超过该值才在开播时跳转续播（避免误跳）。
  static const Duration resumeSeekThreshold = Duration(seconds: 10);

  /// 控制栏自动隐藏延时。
  static const Duration controlsHideDelay = Duration(seconds: 4);

  /// 开播兜底超时：超过该时长仍没收到 playing / duration，
  /// 也强制收起"正在准备"转圈，把播放按钮还给用户。
  static const Duration startupTimeout = Duration(seconds: 20);

  /// 播放记录写盘节流间隔。
  static const Duration historyThrottle = Duration(seconds: 8);

  // ---------------- 存储 ----------------
  static const String boxSources = 'sources.json';
  static const String boxFavorites = 'favorites.json';
  static const String boxHistory = 'history.json';
  static const String boxSearches = 'searches.json';
  static const String boxSyncTombstones = 'sync_tombstones.json';

  static const String prefThemeMode = 'theme_mode';
  static const String prefActiveSource = 'active_source_id';
  static const String prefDefaultRate = 'default_rate';
  static const String prefAutoNext = 'auto_next_episode';
  static const String prefResume = 'resume_playback';
  static const String prefKeepScreenOn = 'keep_screen_on';
  static const String prefMultiSourceSearch = 'multi_source_search';
  static const String prefShowControlsOnStart = 'show_controls_on_start';
  static const String prefHardwareDecode = 'hardware_decode';
  static const String prefEpisodeOrder = 'episode_order';
  static const String prefImageCacheBytes = 'image_cache_bytes';

  // ---------------- 同步 ----------------
  static const Duration syncTimeout = Duration(seconds: 25);

  /// 远端文件路径。挂在根目录下很容易撞上别人的文件，所以默认收进子目录。
  static const String defaultWebDavPath = '/cmsplayer/sync.json';

  /// 局域网同步端口与设备发现端口。
  static const int defaultLanPort = 8765;
  static const int lanDiscoveryPort = 9877;

  static const String prefWebDavUrl = 'sync_webdav_url';
  static const String prefWebDavUser = 'sync_webdav_user';
  static const String prefWebDavPass = 'sync_webdav_pass';
  static const String prefWebDavPath = 'sync_webdav_path';
  static const String prefLanHost = 'sync_lan_host';
  static const String prefLanPort = 'sync_lan_port';
  static const String prefLastSyncAt = 'sync_last_at';
  static const String prefDeviceName = 'sync_device_name';

  // ---------------- 列表 / 详情页 ----------------
  static const List<int> pageSizes = <int>[12, 20, 24, 30, 36, 48];
  static const int defaultGridCrossAxisMobile = 3;
  static const int defaultGridCrossAxisDesktop = 6;

  /// 分类筛选项：排序方式（macCMS 的 `by` 参数）。
  static const Map<String, String> sortOptions = <String, String>{
    'time': '最新更新',
    'hits': '最多播放',
    'score': '最高评分',
    'input': '最多推荐',
  };

  /// 分类筛选项：年代（macCMS 的 `year` 参数）。
  static const List<String> yearOptions = <String>[
    '2026', '2025', '2024', '2023', '2022', '2021', '2020',
    '2019', '2018', '2017', '2016', '2015', '2014', '2013',
    '2012', '2011', '2010', '2000-2009', '1990-1999', '更早',
  ];

  /// 分类筛选项：地区（macCMS 的 `area` 参数）。
  static const List<String> areaOptions = <String>[
    '大陆', '香港', '台湾', '美国', '韩国', '日本', '泰国',
    '印度', '英国', '法国', '德国', '西班牙', '意大利', '其他',
  ];

  /// 内置示例源。仅用于首次启动演示，用户可自行增删。
  static const List<Map<String, String>> builtinSources = <Map<String, String>>[
    <String, String>{
      'name': '海外看（示例）',
      'api': 'https://haiwaikan.com/api.php/provide/vod/',
      'note': '示例源，可能需要代理，可能随时失效',
    },
  ];

  /// 官方源列表（json 数组，元素包含 name / api / note）。
  static const String officialSourceListUrl =
      'https://raw.githubusercontent.com/cms-player/vod-source/main/source.json';

  /// 上述链接的国内镜像。
  static const String officialSourceListMirror =
      'https://mirror.ghproxy.com/https://raw.githubusercontent.com/cms-player/vod-source/main/source.json';
}
