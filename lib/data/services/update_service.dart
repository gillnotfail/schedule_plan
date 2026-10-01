import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/delta_patch.dart';
import 'package:schedule_plan/data/models/app_release.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/services/apk_installer.dart';

/// 当前运行的应用版本。
@immutable
class AppVersionSnapshot {
  const AppVersionSnapshot({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;

  /// 版本号读不出来时不要当成 0 用。
  ///
  /// `versionCode == 0` 会让"比当前版本新的都算更新"永远成立，
  /// 于是每次检查都提示升级；宁可当作"不知道"，直接不检查。
  bool get isKnown => versionCode > 0;

  static Future<AppVersionSnapshot> fromPlatform() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersionSnapshot(
        versionName: info.version,
        versionCode: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (error, stack) {
      AppLogger.e('读取应用版本失败', error: error, stack: stack);
      return const AppVersionSnapshot(versionName: '', versionCode: 0);
    }
  }
}

/// 更新过程中的阶段。界面上每一步的说法都不一样，所以拆开而不是只给一个进度条。
enum UpdatePhase {
  idle,

  /// 正在取清单
  checking,

  /// 已是最新
  upToDate,

  /// 有新版本，等用户决定
  available,

  /// 下载补丁或整包
  downloading,

  /// 正在用本机旧包 + 补丁合成新包
  assembling,

  /// 新包已就绪，可以交给系统安装
  ready,

  /// 已交给系统，等用户在系统弹窗上确认
  installing,

  /// 安装完成（进程通常随即重启）
  installed,

  /// 失败
  failed,

  /// 当前平台不支持应用内自更新
  unsupported,
}

/// 失败原因。界面按这个映射本地化文案，不直接展示底层报错。
enum UpdateFailure {
  /// 清单或包都没取到
  network,

  /// 取到了但内容不可用（结构不认识、没有可用条目）
  manifest,

  /// 清单里没有这个 ABI 的包
  assetMissing,

  /// 下载下来的文件指纹不符
  hashMismatch,

  /// 补丁合成后的包与发布清单对不上
  deltaMismatch,

  /// 磁盘空间不够
  noSpace,

  /// 没拿到「安装未知应用」授权
  installBlocked,

  /// 交给系统安装被拒
  installRejected,

  /// 其它
  unknown,
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.plan,
    this.progress = 0,
    this.failure,
    this.failureDetail,
    this.installAllowed = false,
    this.preparedApkPath,
    this.usedDelta = false,
    this.fellBackToFull = false,
    this.currentVersion = const AppVersionSnapshot(versionName: '', versionCode: 0),
  });

  final UpdatePhase phase;
  final UpdatePlan? plan;

  /// 当前阶段的进度（0~1）。下载是字节比例，合成是按命令数推进。
  final double progress;
  final UpdateFailure? failure;
  final String? failureDetail;

  /// 系统是否已允许本应用安装未知来源的应用。
  final bool installAllowed;

  /// 已准备好的新包路径（[UpdatePhase.ready] 之后才有值）。
  final String? preparedApkPath;

  /// 这次走的是分差补丁。
  final bool usedDelta;

  /// 分差半路失败、已改用整包。界面要如实说明，别让用户以为省了流量。
  final bool fellBackToFull;

  final AppVersionSnapshot currentVersion;

  bool get isBusy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.assembling ||
      phase == UpdatePhase.installing;

  /// 局部更新状态。
  ///
  /// 可空字段（[plan] / [preparedApkPath] / [failure]）必须配一个显式的
  /// `clearXxx` 开关：只用 `??` 的话 `copyWith(plan: null)` 会静默保留旧值，
  /// 于是"已是最新"之后界面还挂着上一版的更新方案——这类 bug 很难从现象反推。
  UpdateState copyWith({
    UpdatePhase? phase,
    UpdatePlan? plan,
    bool clearPlan = false,
    double? progress,
    UpdateFailure? failure,
    String? failureDetail,
    bool clearFailure = false,
    bool? installAllowed,
    String? preparedApkPath,
    bool clearPreparedApk = false,
    bool? usedDelta,
    bool? fellBackToFull,
    AppVersionSnapshot? currentVersion,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      plan: clearPlan ? null : (plan ?? this.plan),
      progress: progress ?? this.progress,
      failure: clearFailure ? null : (failure ?? this.failure),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
      installAllowed: installAllowed ?? this.installAllowed,
      preparedApkPath:
          clearPreparedApk ? null : (preparedApkPath ?? this.preparedApkPath),
      usedDelta: usedDelta ?? this.usedDelta,
      fellBackToFull: fellBackToFull ?? this.fellBackToFull,
      currentVersion: currentVersion ?? this.currentVersion,
    );
  }
}

/// 更新服务需要的"记忆"。抽成窄接口是为了让服务本体不依赖数据库也能单测。
abstract interface class UpdatePreferences {
  Future<bool> autoCheckEnabled();
  Future<int> lastCheckAt();
  Future<int> skippedVersionCode();
  Future<List<String>> mirrorPrefixes();

  Future<void> saveLastCheckAt(int milliseconds);
  Future<void> saveSkippedVersionCode(int versionCode);
  Future<void> saveMirrorPrefixes(List<String> prefixes);
}

class SettingsUpdatePreferences implements UpdatePreferences {
  SettingsUpdatePreferences({SettingsRepository? settings})
      : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;

  @override
  Future<bool> autoCheckEnabled() =>
      _settings.readBool(SettingKeys.updateAutoCheckEnabled);

  @override
  Future<int> lastCheckAt() => _settings.readInt(SettingKeys.updateLastCheckAt);

  @override
  Future<int> skippedVersionCode() =>
      _settings.readInt(SettingKeys.updateSkippedVersionCode);

  @override
  Future<List<String>> mirrorPrefixes() async {
    final raw = await _settings.read(SettingKeys.updateMirrorPrefixes);
    return raw
        .split(RegExp(r'[\r\n,]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  @override
  Future<void> saveLastCheckAt(int milliseconds) =>
      _settings.writeInt(SettingKeys.updateLastCheckAt, milliseconds);

  @override
  Future<void> saveSkippedVersionCode(int versionCode) =>
      _settings.writeInt(SettingKeys.updateSkippedVersionCode, versionCode);

  @override
  Future<void> saveMirrorPrefixes(List<String> prefixes) =>
      _settings.write(SettingKeys.updateMirrorPrefixes, prefixes.join('\n'));
}

/// 应用内自更新。
///
/// 一条完整链路：取清单 → 比对版本 → 择优（分差 or 整包）→ 下载 → 校验 →
/// （分差则）用本机旧包合成 → 再校验 → 交给系统安装。
///
/// 三条设计原则贯穿全流程：
///   1. **绝不放过任何一次校验**。下载的文件按清单给的 SHA-256 校验；
///      分差合成出的包不仅按补丁头校验，还要再和清单里那份整包对一次指纹。
///      任何一步对不上就换路径重来，而不是"差不多就装"。
///   2. **任何一步失败都能退到整包**。分差只是省流量，不是必需品；
///      它出问题不应该让用户升不了级。
///   3. **失败要说清楚是哪一步**。阶段和原因分开报，界面才好讲人话。
class UpdateService extends ChangeNotifier {
  UpdateService({
    ApkInstaller? installer,
    http.Client? client,
    UpdatePreferences? preferences,
  })  : _installer = installer ?? ApkInstaller(),
        _client = client ?? http.Client(),
        _preferences = preferences ?? SettingsUpdatePreferences();

  /// GitHub 上的仓库（发布链路的主体，也是最权威的一份）。
  static const String githubRepositorySlug = 'gillnotfail/schedule_plan';

  /// Gitee 上的镜像仓库。老师的手机大多在国内，Gitee 是唯一一条
  /// **通常不需要代理就能连上**的来路，所以清单与安装包都让它排第一。
  static const String giteeRepositorySlug = 'jeo-xie/schedule_plan';

  /// 兼容旧调用：过去只有一个仓库，指的是 GitHub 那份。
  static const String repositorySlug = githubRepositorySlug;

  /// 清单文件在仓库里的路径。
  static const String manifestPath = 'updates/latest.json';

  /// 自动检查的最短间隔：一天一次。启动时检查一下，比"每次打开都请求"体面得多。
  static const Duration autoCheckInterval = Duration(hours: 24);

  /// 下载时允许的"静默"时长：超过这么久没有任何数据就判定失败，换下一个地址。
  static const Duration stallTimeout = Duration(seconds: 30);

  /// 建连超时。
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 预留的磁盘余量：装完包还要解压、还要留出系统缓存的空间。
  static const int diskSlackBytes = 16 * 1024 * 1024;

  final ApkInstaller _installer;
  final http.Client _client;
  final UpdatePreferences _preferences;

  UpdateState _state = const UpdateState();
  UpdateState get state => _state;

  bool _cancelled = false;
  bool _checking = false;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  /// 当前设备的 ABI 名（与构建产物后缀一致）。非 Android 返回空串。
  static String currentAbiName() {
    if (!Platform.isAndroid) {
      return '';
    }
    const names = <Abi, String>{
      Abi.androidArm64: 'arm64-v8a',
      Abi.androidArm: 'armeabi-v7a',
      Abi.androidX64: 'x86_64',
      Abi.androidIA32: 'x86',
    };
    return names[Abi.current()] ?? '';
  }

  /// 启动时的静默检查：只在开关打开、且距上次检查超过一天时才真的发请求。
  ///
  /// 返回是否有新版可更新。整个过程不打扰用户，失败也只记日志。
  Future<bool> autoCheckIfDue() async {
    try {
      if (!await _preferences.autoCheckEnabled()) {
        return false;
      }
      final last = await _preferences.lastCheckAt();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last > 0 && now - last < autoCheckInterval.inMilliseconds) {
        return false;
      }
      await check();
      return _state.phase == UpdatePhase.available;
    } catch (error, stack) {
      AppLogger.e('自动检查更新失败', error: error, stack: stack);
      return false;
    }
  }

  /// 取清单并算出更新方案。
  ///
  /// [force] 为 true 时忽略「跳过这一版」——用户手动点检查更新时，
  /// 之前跳过过的版本也该再问一次。
  Future<void> check({bool force = false}) async {
    if (_checking) {
      return;
    }
    _checking = true;
    _cancelled = false;
    _setState(_state.copyWith(
      phase: UpdatePhase.checking,
      progress: 0,
      clearFailure: true,
    ));

    try {
      if (!supportsInAppUpdate) {
        _setState(_state.copyWith(phase: UpdatePhase.unsupported));
        return;
      }
      final version = await AppVersionSnapshot.fromPlatform();
      _setState(_state.copyWith(currentVersion: version));
      if (!version.isKnown) {
        // 版本号都读不出来，谈不上"比谁新"，如实报失败比乱提示强。
        _fail(UpdateFailure.unknown, '无法读取当前版本号');
        return;
      }

      final mirrors = await _preferences.mirrorPrefixes();
      final manifest = await _fetchManifest(mirrors);
      await _preferences.saveLastCheckAt(DateTime.now().millisecondsSinceEpoch);
      if (manifest == null) {
        _fail(UpdateFailure.manifest, '清单不可用');
        return;
      }

      final abi = currentAbiName();
      // 先只按版本号判断有没有新版。没有新版就到此为止——
      // 不要为了走分差去哈希一个二十多兆的 APK。
      final coarse = manifest.plan(
        currentVersionCode: version.versionCode,
        currentVersionName: version.versionName,
        abi: abi,
        mirrorPrefixes: mirrors,
      );
      if (coarse == null) {
        _setState(_state.copyWith(
          phase: UpdatePhase.upToDate,
          clearPlan: true,
          progress: 0,
        ));
        return;
      }

      final skipped = await _preferences.skippedVersionCode();
      if (!force && skipped > 0 && coarse.latest.versionCode <= skipped) {
        // 用户跳过的是"这一版"，出了更新的版本会自动失效。
        _setState(_state.copyWith(phase: UpdatePhase.upToDate, clearPlan: true));
        return;
      }

      // 走到这里说明确实有新版，此时才值得算本机 APK 的指纹来判断分差。
      final refined = await _planWithBaseHash(
        manifest: manifest,
        version: version,
        abi: abi,
        mirrors: mirrors,
      );
      final installAllowed = await _installer.canInstallPackages();
      _setState(_state.copyWith(
        phase: UpdatePhase.available,
        plan: refined,
        progress: 0,
        installAllowed: installAllowed,
      ));
    } catch (error, stack) {
      AppLogger.e('检查更新失败', error: error, stack: stack);
      _fail(UpdateFailure.network, '$error');
    } finally {
      _checking = false;
    }
  }

  /// 记下"跳过这一版"。
  Future<void> skipCurrentPlan() async {
    final plan = _state.plan;
    if (plan == null) {
      return;
    }
    await _preferences.saveSkippedVersionCode(plan.latest.versionCode);
    _setState(_state.copyWith(phase: UpdatePhase.upToDate, clearPlan: true));
  }

  /// 下载并按需合成出新包，成功后进入 [UpdatePhase.ready]。
  Future<void> prepare() async {
    final plan = _state.plan;
    if (plan == null || _state.isBusy) {
      return;
    }
    _cancelled = false;
    _setState(_state.copyWith(
      progress: 0,
      clearFailure: true,
      clearPreparedApk: true,
      usedDelta: false,
      fellBackToFull: false,
    ));

    final workDirPath = await _installer.prepareWorkDir();
    if (workDirPath == null) {
      _fail(UpdateFailure.unknown, '无法创建工作目录');
      return;
    }
    final workDir = Directory(workDirPath);

    // 磁盘空间：分差要同时放下补丁、本机旧包和新包。
    final needs = plan.downloadBytes +
        (plan.usesDelta ? plan.asset.size : 0) +
        diskSlackBytes;
    final free = await _installer.freeDiskBytes();
    if (free > 0 && free < needs) {
      _fail(UpdateFailure.noSpace,
          '需要 ${formatBytes(needs)}，可用 ${formatBytes(free)}');
      return;
    }

    var usedDelta = false;
    if (plan.usesDelta) {
      try {
        final built = await _prepareViaDelta(plan, workDir);
        if (built != null) {
          usedDelta = true;
          _setState(_state.copyWith(
            phase: UpdatePhase.ready,
            progress: 1,
            preparedApkPath: built,
            usedDelta: true,
          ));
          return;
        }
      } catch (error, stack) {
        // 分差失败不是终点——退回整包继续，用户在意的只是"能不能升上去"。
        AppLogger.w('分差路径失败，改用完整包：$error');
        AppLogger.e('分差路径失败', error: error, stack: stack);
        if (_cancelled) {
          _setState(_state.copyWith(phase: UpdatePhase.available, progress: 0));
          return;
        }
        _setState(_state.copyWith(fellBackToFull: true));
      }
    }

    try {
      final built = await _prepareViaFullPackage(plan, workDir);
      _setState(_state.copyWith(
        phase: UpdatePhase.ready,
        progress: 1,
        preparedApkPath: built,
        usedDelta: usedDelta,
      ));
    } catch (error, stack) {
      AppLogger.e('下载完整包失败', error: error, stack: stack);
      if (_cancelled) {
        _setState(_state.copyWith(phase: UpdatePhase.available, progress: 0));
        return;
      }
      _fail(UpdateFailure.network, '$error');
    }
  }

  /// 把已就绪的新包交给系统安装。
  Future<void> install() async {
    final path = _state.preparedApkPath;
    if (path == null) {
      return;
    }
    if (!await _installer.canInstallPackages()) {
      _fail(UpdateFailure.installBlocked, '未获得安装未知应用的授权');
      return;
    }

    _installer.onInstallResult = _onInstallResult;
    _setState(_state.copyWith(phase: UpdatePhase.installing));
    final started = await _installer.install(path);
    if (!started) {
      _fail(UpdateFailure.installRejected, '系统安装器拒绝了这次安装');
    }
  }

  /// 跳到「安装未知应用」授权页。
  Future<void> openInstallPermissionSettings() =>
      _installer.openInstallPermissionSettings();

  /// 用户手动改了镜像前缀后保存。
  Future<void> saveMirrorPrefixes(List<String> prefixes) async {
    await _preferences.saveMirrorPrefixes(prefixes);
    // 地址变了，之前的结论就不再适用，清干净免得拿着旧方案去下载。
    _setState(_state.copyWith(
      clearPlan: true,
      clearPreparedApk: true,
      phase: UpdatePhase.idle,
      progress: 0,
    ));
  }

  Future<List<String>> mirrorPrefixes() => _preferences.mirrorPrefixes();

  /// 取消正在进行的下载/合成。
  ///
  /// 只置标志位——下载循环与合成各自在合适的粒度上检查它，
  /// 所以点一下不需要等下一个网络分片回来就能停下。
  void cancel() {
    if (_state.isBusy) {
      _cancelled = true;
    }
  }

  /// 用户从系统确认框回来后（或安装失败后）把状态摆正，方便重试。
  void resetAfterInstallAttempt() {
    if (_state.phase == UpdatePhase.installing) {
      _setState(_state.copyWith(phase: UpdatePhase.ready));
    }
  }

  /// 外部已经把版本追平了。
  ///
  /// 系统装完新包会把进程杀掉重启，"安装成功"的那次回执经常送不到，
  /// 所以回前台后主动比对一次版本号更可靠——只要版本已经到了目标值，
  /// 就该把状态显示成"已安装"，而不是让用户对着"等待确认"发愣。
  void markInstalledExternally() {
    _setState(_state.copyWith(
      phase: UpdatePhase.installed,
      clearPlan: true,
      clearPreparedApk: true,
      progress: 0,
    ));
  }

  // -------------------------------------------------------------------------
  // 内部实现
  // -------------------------------------------------------------------------

  /// 清单地址列表，**Gitee 优先、GitHub 兜底、jsDelivr 最后**。
  ///
  /// 三条来路各有用处，顺序不是随手排的：
  ///   · Gitee raw：国内直连，是老师手机上唯一一条通常不需要代理的来路；
  ///   · GitHub raw：内容最权威（补丁与安装包的原产地），但国内常常连不上；
  ///   · jsDelivr：GitHub 的 CDN 兜底，代价是对分支有最长 12 小时缓存
  ///     （所以发布脚本里那步清缓存不能省，见 `tool/release.py`）。
  ///
  /// Gitee 那条会带一个 `?t=` 时间戳：它自己的 raw 也会被 CDN 缓存，
  /// 加一个每次都变的查询串才能"发完立刻可见"。清单只有几 KB，
  /// 这点缓存收益不值得拿"晚半天才看到更新"去换。
  ///
  /// [epochSeconds] 只为测试可断言而存在，生产调用不传。
  static List<String> manifestUrls(
    List<String> mirrorPrefixes, {
    int? epochSeconds,
  }) {
    final stamp =
        epochSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final direct = <String>[
      'https://gitee.com/$giteeRepositorySlug/raw/main/$manifestPath?t=$stamp',
      'https://raw.githubusercontent.com/$githubRepositorySlug/main/$manifestPath',
      'https://cdn.jsdelivr.net/gh/$githubRepositorySlug@main/$manifestPath',
    ];
    return <String>[
      ...direct,
      for (final prefix in mirrorPrefixes)
        for (final url in direct) '$prefix$url',
    ];
  }

  Future<UpdateManifest?> _fetchManifest(List<String> mirrors) async {
    for (final url in manifestUrls(mirrors)) {
      try {
        final response = await _client.get(Uri.parse(url)).timeout(connectTimeout);
        if (response.statusCode != 200) {
          AppLogger.w('清单地址返回 ${response.statusCode}：$url');
          continue;
        }
        final manifest = UpdateManifest.tryParse(response.body);
        if (manifest != null) {
          return manifest;
        }
        AppLogger.w('清单内容不可用：$url');
      } catch (error, stack) {
        AppLogger.e('取清单失败：$url', error: error, stack: stack);
      }
    }
    return null;
  }

  /// 算出本机已装 APK 的指纹，再让清单给出带分差的方案。
  ///
  /// 指纹算不出来（拿不到路径、读不动文件）不是错误：退回"只能整包更新"，
  /// 用户照样能升级，只是多下点流量。
  Future<UpdatePlan?> _planWithBaseHash({
    required UpdateManifest manifest,
    required AppVersionSnapshot version,
    required String abi,
    required List<String> mirrors,
  }) async {
    final coarse = manifest.plan(
      currentVersionCode: version.versionCode,
      currentVersionName: version.versionName,
      abi: abi,
      mirrorPrefixes: mirrors,
    );
    if (coarse == null) {
      return null;
    }
    // 目标版本压根没给这个 ABI 准备补丁，就没必要去哈希本机 APK。
    final hasDeltaCandidate = coarse.latest.deltas.any(
      (delta) =>
          delta.fromVersionCode == version.versionCode && delta.abi == abi,
    );
    if (!hasDeltaCandidate) {
      return coarse;
    }

    String? baseHash;
    try {
      final basePath = await _installer.installedApkPath();
      if (basePath != null && File(basePath).existsSync()) {
        baseHash = await sha256OfFile(basePath);
      }
    } catch (error, stack) {
      AppLogger.e('计算本机 APK 指纹失败，本次按整包处理', error: error, stack: stack);
    }
    if (baseHash == null) {
      return coarse;
    }
    return manifest.plan(
      currentVersionCode: version.versionCode,
      currentVersionName: version.versionName,
      abi: abi,
      baseApkSha256: baseHash,
      mirrorPrefixes: mirrors,
    );
  }

  /// 分差路径：下补丁 → 校验 → 用本机旧包合成 → 与发布清单交叉校验。
  Future<String?> _prepareViaDelta(UpdatePlan plan, Directory workDir) async {
    final delta = plan.delta;
    final basePath = await _installer.installedApkPath();
    if (delta == null || basePath == null) {
      return null;
    }

    _setState(_state.copyWith(phase: UpdatePhase.downloading, progress: 0));
    final patchPath = await _download(
      plan: plan,
      useDelta: true,
      workDir: workDir,
      expectedBytes: delta.size,
      expectedSha256: delta.sha256,
    );
    if (patchPath == null) {
      return null;
    }

    _setState(_state.copyWith(phase: UpdatePhase.assembling, progress: 0));
    final patch = DeltaPatch.parseGzipped(await File(patchPath).readAsBytes());
    final outputPath =
        '${workDir.path}/update-${plan.latest.versionCode}-${delta.abi}.apk';
    await patch.apply(basePath: basePath, outputPath: outputPath);

    // 交叉校验：补丁头里的目标指纹来自补丁文件本身，而这里再和清单里
    // 那份整包的指纹比一次。两个独立来源必须一致——这比只看其中一个可靠得多。
    final produced = await sha256OfFile(outputPath);
    if (produced != plan.asset.sha256) {
      await _quietlyDelete(File(outputPath));
      throw DeltaPatchException(
        DeltaPatchErrorKind.targetMismatch,
        '合成包与发布清单不一致：期望 ${plan.asset.sha256}，实际 $produced',
      );
    }
    // 拿到手就用不上了，顺手清掉省空间。
    await _quietlyDelete(File(patchPath));
    return outputPath;
  }

  /// 整包路径：下载 → 校验指纹。
  Future<String> _prepareViaFullPackage(
      UpdatePlan plan, Directory workDir) async {
    _setState(_state.copyWith(phase: UpdatePhase.downloading, progress: 0));
    final path = await _download(
      plan: plan,
      useDelta: false,
      workDir: workDir,
      expectedBytes: plan.asset.size,
      expectedSha256: plan.asset.sha256,
    );
    if (path == null) {
      throw const DeltaPatchException(
        DeltaPatchErrorKind.io,
        '所有下载地址都失败了',
      );
    }
    return path;
  }

  /// 逐个地址尝试下载，成功后返回落地路径。
  ///
  /// 任一地址下载完成但指纹不符时**会删掉重下**并换下一个地址：
  /// 校验失败最常见的成因是镜像回了半份内容或中间被改过，
  /// 与其相信它，不如换条路。
  Future<String?> _download({
    required UpdatePlan plan,
    required bool useDelta,
    required Directory workDir,
    required int expectedBytes,
    required String expectedSha256,
  }) async {
    final fileName = useDelta ? plan.delta!.file : plan.asset.file;
    final target = File('${workDir.path}/$fileName');
    final urls = plan.candidateUrls(forDelta: useDelta);

    for (var i = 0; i < urls.length; i++) {
      try {
        await _downloadOne(
          url: urls[i],
          target: target,
          expectedBytes: expectedBytes,
        );
        final actual = await sha256OfFile(target.path);
        if (actual == expectedSha256) {
          return target.path;
        }
        AppLogger.w('${sourceLabelOf(urls[i])} 下载内容指纹不符（$actual），换下一个地址');
        await _quietlyDelete(target);
      } catch (error, stack) {
        AppLogger.e('从 ${sourceLabelOf(urls[i])} 下载失败：${urls[i]}',
            error: error, stack: stack);
        if (_cancelled) {
          return null;
        }
      }
    }
    return null;
  }

  /// 尽力删除临时文件：删不掉只是留下垃圾，不该把整个更新流程带崩。
  Future<void> _quietlyDelete(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (error, stack) {
      AppLogger.e('清理临时文件失败：${file.path}', error: error, stack: stack);
    }
  }

  Future<void> _downloadOne({
    required String url,
    required File target,
    required int expectedBytes,
  }) async {
    final response =
        await _client.send(http.Request('GET', Uri.parse(url))).timeout(
              connectTimeout,
            );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    var received = 0;
    final total = expectedBytes > 0
        ? expectedBytes
        : (response.contentLength ?? 0);
    try {
      // 对"卡住不动"的连接也要给个了断，否则用户会钉在 0% 上无限等。
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        if (_cancelled) {
          throw const DeltaPatchException(DeltaPatchErrorKind.io, '已取消');
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _setState(_state.copyWith(progress: (received / total).clamp(0.0, 1.0)));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total > 0 && received != total) {
      throw HttpException(
        '下载不完整：期望 $total 字节，收到 $received',
        uri: Uri.parse(url),
      );
    }
  }

  void _onInstallResult(ApkInstallOutcome outcome) {
    if (outcome.isSuccess) {
      _setState(_state.copyWith(phase: UpdatePhase.installed));
      return;
    }
    if (outcome.isCancelled) {
      // 用户取消不是错误，回到"可以安装"让 ta 想装时再点。
      _setState(_state.copyWith(phase: UpdatePhase.ready));
      return;
    }
    _fail(UpdateFailure.installRejected, outcome.message);
  }

  void _fail(UpdateFailure failure, String? detail) {
    _setState(_state.copyWith(
      phase: UpdatePhase.failed,
      failure: failure,
      failureDetail: detail,
      progress: 0,
    ));
  }

  void _setState(UpdateState next) {
    _state = next;
    notifyListeners();
  }
}

/// 给日志用的来源名：把一长串地址压成 `gitee` / `github` / 域名。
///
/// 更新失败时用户报回来的往往是"下载不动"，而真正要分辨的是**是哪一条来路
/// 不通**——清单里同时有 Gitee 和 GitHub 两份地址，日志里全是原始 URL 时
/// 根本看不出走的是哪条。域名是唯一可靠的判据（不能靠"包含 gitee"这种
/// 子串匹配，代理前缀会把别人的域名套在前面）。
String sourceLabelOf(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) {
    return url;
  }
  if (host == 'gitee.com' || host.endsWith('.gitee.com')) {
    return 'Gitee';
  }
  if (host == 'github.com' ||
      host.endsWith('.github.com') ||
      host.endsWith('.githubusercontent.com')) {
    return 'GitHub';
  }
  if (host.endsWith('.jsdelivr.net') || host == 'jsdelivr.net') {
    return 'jsDelivr';
  }
  return host;
}
