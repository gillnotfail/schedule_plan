import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 应用内更新清单（`updates/latest.json`）的模型层。
///
/// 这里**只做解析与取舍决策，不碰网络也不碰文件系统**——所以"该不该更新、
/// 该走分差还是整包、某个条目可不可信"这些判断全都能用纯单测锁住。
/// 真正发请求、下载、合成、安装是 [UpdateService] 的事。
///
/// 清单结构：
/// ```json
/// {
///   "schemaVersion": 1,
///   "generatedAt": "2026-09-27T10:00:00+08:00",
///   "minSupportedVersionCode": 1,
///   "assetsBase": "https://gitee.com/<owner>/<repo>/releases/download",
///   "assetsBases": [
///     "https://gitee.com/<owner>/<repo>/releases/download",
///     "https://github.com/<owner>/<repo>/releases/download"
///   ],
///   "releases": [
///     {
///       "versionCode": 2, "versionName": "1.0.1", "tag": "v1.0.1",
///       "publishedAt": "...", "notes": ["...", "..."],
///       "assets": [{"abi":"arm64-v8a","file":"app-arm64-v8a-release.apk",
///                   "size": 24003104, "sha256": "..."}],
///       "deltas": [{"fromVersionCode": 1, "abi": "arm64-v8a",
///                   "file": "patch-1-2-arm64-v8a.spdp", "size": 123456,
///                   "targetSize": 24003104,
///                   "sha256": "...", "baseSha256": "..."}]
///     }
///   ]
/// }
/// ```
/// `assetsBases` 是**可选**的多源列表（Gitee 在前、GitHub 兜底），
/// `assetsBase` 是给老客户端留的单数字段，两者都由 `tool/release.py` 写。
/// `releases` 按 `versionCode` **从新到旧**排列，这样"展示从我这一版到最新
/// 之间的全部更新说明"就是一次前缀扫描，不需要再排序。
@immutable
class UpdateManifest {
  const UpdateManifest({
    required this.schemaVersion,
    required this.assetsBase,
    required this.releases,
    this.assetsBases = const <String>[],
    this.generatedAt,
    this.minSupportedVersionCode = 0,
  });

  /// 本 App 认识的清单结构版本。
  static const int supportedSchemaVersion = 1;

  /// 分差补丁要"值得用"，至少得比整包小到这个比例以下。
  ///
  /// 分差多了一条"从本机旧包合成"的链路，风险天然比整包高；
  /// 如果省不下多少，不如直接下整包。九折是个保守的起点。
  static const double deltaWorthwhileRatio = 0.9;

  final int schemaVersion;

  /// **单数**附件根地址，老版本客户端唯一认识的那个字段。
  ///
  /// 保留它不是为了自己用，而是因为已经装在老师手机上的旧版本只会读这一个
  /// 字段。所以生成端必须继续写、而且必须写一个**发布时当场验证过能匿名下载**
  /// 的地址（见 `tool/release.py` 的 `verify_asset_urls`）。
  final String assetsBase;

  /// 附件根地址候选，**按优先级**排列。
  ///
  /// 本项目同时托管在 Gitee 与 GitHub：国内 Gitee 直连更稳，GitHub 更权威，
  /// 两边都放一份安装包，客户端从上往下试第一个能下的。字段可缺省——
  /// 缺省时退回单数的 [assetsBase]，于是老清单与手写的清单都还能用。
  ///
  /// **不能把 schemaVersion 提上去**：老客户端见到更高的结构版本会直接判
  /// "这份清单不可用"，等于把已经装机的用户全锁死在旧版本上。新增字段必须
  /// 是可选的、老解析器忽略得了的。
  final List<String> assetsBases;

  final List<AppRelease> releases;
  final DateTime? generatedAt;
  final int minSupportedVersionCode;

  AppRelease? get latest => releases.isEmpty ? null : releases.first;

  /// 实际可用的附件根地址（按优先级）。
  ///
  /// 新清单给 [assetsBases]，老清单只有 [assetsBase]；这里统一成一个口径，
  /// 上层不必关心清单是哪个年代生成的。
  List<String> get assetBaseList {
    if (assetsBases.isNotEmpty) {
      return assetsBases;
    }
    return assetsBase.isEmpty ? const <String>[] : <String>[assetsBase];
  }

  /// 解析清单。[body] 是清单文件的原始文本。
  ///
  /// 返回 `null` 表示**这份清单不可用**（不是合法 JSON、结构版本不认识、
  /// 没有 releases、或字段缺失到无法判断）。调用方按"这次检查失败"处理，
  /// 绝不能拿一份半懂的清单去指导安装。
  static UpdateManifest? tryParse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final schema = _asInt(decoded['schemaVersion']);
    if (schema == null || schema > supportedSchemaVersion) {
      // 结构版本更高 = 生成端用了本 App 不认识的说法，宁可当作没拿到。
      return null;
    }
    final rawReleases = decoded['releases'];
    if (rawReleases is! List || rawReleases.isEmpty) {
      return null;
    }

    final releases = <AppRelease>[];
    for (final item in rawReleases) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final release = AppRelease.tryParse(item);
      if (release != null) {
        releases.add(release);
      }
    }
    if (releases.isEmpty) {
      return null;
    }
    // 生成端已经排好序，但清单可能被手改过。这里兜一次底，
    // 保证"最新在最前"这个前提在后续逻辑里真的成立。
    releases.sort((a, b) => b.versionCode.compareTo(a.versionCode));

    return UpdateManifest(
      schemaVersion: schema,
      assetsBase: _asString(decoded['assetsBase']) ?? '',
      assetsBases: _asStringList(decoded['assetsBases']),
      releases: releases,
      generatedAt: _asDateTime(decoded['generatedAt']),
      minSupportedVersionCode: _asInt(decoded['minSupportedVersionCode']) ?? 0,
    );
  }

  /// 比 [versionCode] 新的全部版本，按从新到旧。
  ///
  /// 用于在更新页把"从我这一版到最新"之间的更新说明一次讲完——
  /// 用户装的是 1.0.0，中间跳过的 1.0.1 / 1.0.2 改了什么，全都该看到。
  List<AppRelease> releasesAfter(int versionCode) =>
      releases.where((r) => r.versionCode > versionCode).toList();

  /// 给出"要不要更新、怎么更"的结论。返回 `null` 表示无需更新或无法更新。
  ///
  /// [currentVersionCode] 来自 `PackageInfo.buildNumber`；
  /// [abi] 是设备 ABI（`arm64-v8a` 等）；
  /// [baseApkSha256] 是本机已装 APK 的指纹，用于判断分差补丁是否适用；
  /// 传 `null` 表示还没算出来（此时只会考虑整包）。
  UpdatePlan? plan({
    required int currentVersionCode,
    required String currentVersionName,
    required String abi,
    String? baseApkSha256,
    List<String> mirrorPrefixes = const <String>[],
  }) {
    final newer = releasesAfter(currentVersionCode);
    if (newer.isEmpty) {
      return null;
    }
    final target = newer.first;
    final asset = target.assetFor(abi);
    if (asset == null) {
      // 该版本没有为这个 ABI 提供包，不能硬塞一个别的架构的包进去。
      return null;
    }

    // 版本太老时禁用分差：这类用户本来就没有对应的基准包，
    // 而且跨太多版本的分差收益也不确定。
    final allowDelta = currentVersionCode >= minSupportedVersionCode;
    ReleaseDelta? delta;
    if (allowDelta && baseApkSha256 != null && baseApkSha256.isNotEmpty) {
      final candidate = target.deltaFor(
        fromVersionCode: currentVersionCode,
        abi: abi,
        baseSha256: baseApkSha256,
      );
      // 只接受"确实省得多"的补丁：省得少就不值当多担一条合成链路的风险。
      if (candidate != null &&
          candidate.size < asset.size * deltaWorthwhileRatio) {
        delta = candidate;
      }
    }

    return UpdatePlan(
      latest: target,
      changelog: newer,
      asset: asset,
      delta: delta,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      assetsBases: assetBaseList,
      mirrorPrefixes: mirrorPrefixes,
      deltaBlockedByAge: !allowDelta,
    );
  }
}

/// 一个版本。
@immutable
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.tag,
    required this.notes,
    required this.assets,
    required this.deltas,
    this.publishedAt,
  });

  final int versionCode;
  final String versionName;
  final String tag;
  final List<String> notes;
  final List<ReleaseAsset> assets;
  final List<ReleaseDelta> deltas;
  final DateTime? publishedAt;

  static AppRelease? tryParse(Map<String, dynamic> json) {
    final versionCode = _asInt(json['versionCode']);
    final versionName = _asString(json['versionName']);
    if (versionCode == null || versionName == null || versionName.isEmpty) {
      return null;
    }
    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) {
          final asset = ReleaseAsset.tryParse(item);
          if (asset != null && asset.isVerifiable) {
            assets.add(asset);
          }
        }
      }
    }
    final deltas = <ReleaseDelta>[];
    final rawDeltas = json['deltas'];
    if (rawDeltas is List) {
      for (final item in rawDeltas) {
        if (item is Map<String, dynamic>) {
          final delta = ReleaseDelta.tryParse(item);
          if (delta != null && delta.isVerifiable) {
            deltas.add(delta);
          }
        }
      }
    }
    if (assets.isEmpty) {
      // 没有任何可校验的包 = 这一版没法装，不如不提。
      return null;
    }

    final notes = <String>[];
    final rawNotes = json['notes'];
    if (rawNotes is List) {
      for (final note in rawNotes) {
        if (note is String && note.trim().isNotEmpty) {
          notes.add(note.trim());
        }
      }
    }

    return AppRelease(
      versionCode: versionCode,
      versionName: versionName,
      tag: _asString(json['tag']) ?? 'v$versionName',
      notes: notes,
      assets: assets,
      deltas: deltas,
      publishedAt: _asDateTime(json['publishedAt']),
    );
  }

  ReleaseAsset? assetFor(String abi) {
    for (final asset in assets) {
      if (asset.abi == abi) {
        return asset;
      }
    }
    return null;
  }

  ReleaseDelta? deltaFor({
    required int fromVersionCode,
    required String abi,
    required String baseSha256,
  }) {
    for (final delta in deltas) {
      if (delta.fromVersionCode == fromVersionCode &&
          delta.abi == abi &&
          delta.baseSha256.toLowerCase() == baseSha256.toLowerCase()) {
        return delta;
      }
    }
    return null;
  }
}

/// 可直接下载并安装的完整包。
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.abi,
    required this.file,
    required this.size,
    required this.sha256,
    this.absoluteUrl,
  });

  final String abi;

  /// 相对路径（release 附件名）。绝对地址由 [urlFor] 拼出来，
  /// 这样换镜像只要换前缀，不用改清单。
  final String file;
  final int size;
  final String sha256;

  /// 清单里给了完整地址时优先用它。
  final String? absoluteUrl;

  static ReleaseAsset? tryParse(Map<String, dynamic> json) {
    final abi = _asString(json['abi']);
    final file = _asString(json['file']);
    final size = _asInt(json['size']);
    final sha256 = _asString(json['sha256']);
    if (abi == null || file == null || size == null || sha256 == null) {
      return null;
    }
    return ReleaseAsset(
      abi: abi,
      file: file,
      size: size,
      sha256: sha256,
      absoluteUrl: _asString(json['url']),
    );
  }

  /// 缺大小或指纹的条目一律不可用：装一个没校验过的包，
  /// 出问题时连"是下载坏了还是包本身就坏"都分不清。
  bool get isVerifiable => size > 0 && isSha256(sha256);

  String urlFor(String assetsBase, String tag) =>
      absoluteUrl ?? '$assetsBase/$tag/$file';
}

/// 分差补丁条目。
@immutable
class ReleaseDelta {
  const ReleaseDelta({
    required this.fromVersionCode,
    required this.abi,
    required this.file,
    required this.size,
    required this.targetSize,
    required this.sha256,
    required this.baseSha256,
    this.absoluteUrl,
  });

  /// 这份补丁只对"本机装的是这个 versionCode"有意义。
  final int fromVersionCode;
  final String abi;
  final String file;

  /// 补丁文件本身的大小（下载量）。
  final int size;

  /// 合成出来的新包大小，用于提前检查磁盘空间。
  final int targetSize;

  /// 补丁文件的指纹。
  final String sha256;

  /// **本机基础包**必须有的指纹。对不上就是补丁不适用，改走整包。
  final String baseSha256;

  final String? absoluteUrl;

  static ReleaseDelta? tryParse(Map<String, dynamic> json) {
    final fromVersionCode = _asInt(json['fromVersionCode']);
    final abi = _asString(json['abi']);
    final file = _asString(json['file']);
    final size = _asInt(json['size']);
    final targetSize = _asInt(json['targetSize']);
    final sha256 = _asString(json['sha256']);
    final baseSha256 = _asString(json['baseSha256']);
    if (fromVersionCode == null ||
        abi == null ||
        file == null ||
        size == null ||
        targetSize == null ||
        sha256 == null ||
        baseSha256 == null) {
      return null;
    }
    return ReleaseDelta(
      fromVersionCode: fromVersionCode,
      abi: abi,
      file: file,
      size: size,
      targetSize: targetSize,
      sha256: sha256,
      baseSha256: baseSha256,
      absoluteUrl: _asString(json['url']),
    );
  }

  bool get isVerifiable =>
      size > 0 && targetSize > 0 && isSha256(sha256) && isSha256(baseSha256);

  String urlFor(String assetsBase, String tag) =>
      absoluteUrl ?? '$assetsBase/$tag/$file';
}

/// 「更新到哪一版、怎么更」的结论。
@immutable
class UpdatePlan {
  const UpdatePlan({
    required this.latest,
    required this.changelog,
    required this.asset,
    required this.currentVersionCode,
    required this.currentVersionName,
    this.assetsBases = const <String>[],
    this.delta,
    this.mirrorPrefixes = const <String>[],
    this.deltaBlockedByAge = false,
  });

  final AppRelease latest;

  /// 从当前版本之后到最新的全部版本，从新到旧。
  final List<AppRelease> changelog;
  final ReleaseAsset asset;
  final ReleaseDelta? delta;
  final int currentVersionCode;
  final String currentVersionName;

  /// 附件根地址候选，**按优先级**（见 [UpdateManifest.assetsBases]）。
  final List<String> assetsBases;
  final List<String> mirrorPrefixes;

  /// 因为当前版本低于清单声明的最低支持版本，所以没给分差。
  final bool deltaBlockedByAge;

  bool get usesDelta => delta != null;

  /// 需要下载的字节数（走分差就是补丁大小）。
  int get downloadBytes => delta?.size ?? asset.size;

  /// 完整包大小，用于在界面上对比"省了多少"。
  int get fullBytes => asset.size;

  /// 用分差时省下的比例（0~1）。走整包时为 0。
  double get savedRatio =>
      fullBytes == 0 ? 0 : 1 - (downloadBytes / fullBytes).clamp(0.0, 1.0);

  /// 生成下载候选地址：**多源依次尝试，镜像前缀最后兜底**。
  ///
  /// 顺序是刻意的——
  ///   1. 清单里给的源，按清单的顺序（生成端把国内直连快的排前面）；
  ///   2. 用户自己配的镜像前缀。这些前缀服务（ghproxy 之类）只对 GitHub
  ///      地址有意义，排最后是因为它们多一跳、也更容易半路失效。
  ///
  /// 条目自带完整地址（清单里写了 `url`）时它就是唯一来路：这种地址的域名
  /// 是生成端特意指定的，再往上套别的镜像前缀没有意义。
  List<String> candidateUrls({required bool forDelta}) {
    final delta = this.delta;
    if (forDelta && delta != null) {
      return _urlsFrom(delta.absoluteUrl,
          (base) => delta.urlFor(base, latest.tag));
    }
    return _urlsFrom(asset.absoluteUrl,
        (base) => asset.urlFor(base, latest.tag));
  }

  /// 把"清单里的源"与"用户配的镜像前缀"拼成最终候选列表。
  ///
  /// [absolute] 非空表示条目自带完整地址，这种地址的域名是生成端特意指定的，
  /// 再往上套别的镜像前缀没有意义，直接当唯一来路。
  List<String> _urlsFrom(String? absolute, String Function(String base) build) {
    if (absolute != null) {
      return <String>[absolute];
    }
    final direct = <String>[
      for (final base in assetsBases) build(base),
    ];
    if (direct.isEmpty) {
      return const <String>[];
    }
    if (mirrorPrefixes.isEmpty) {
      return direct;
    }
    return <String>[
      ...direct,
      for (final prefix in mirrorPrefixes)
        for (final url in direct) '$prefix$url',
    ];
  }
}

/// 是不是一个合法的 SHA-256 十六进制串（64 位十六进制）。
bool isSha256(String value) {
  if (value.length != 64) {
    return false;
  }
  for (var i = 0; i < 64; i++) {
    final code = value.codeUnitAt(i);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLowerHex = code >= 0x61 && code <= 0x66;
    final isUpperHex = code >= 0x41 && code <= 0x46;
    if (!isDigit && !isLowerHex && !isUpperHex) {
      return false;
    }
  }
  return true;
}

/// 人类可读的字节数，用于"下载 1.2 MB，省掉 21.7 MB"这类文案。
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // 小于 10 时保留一位小数，"1.2 MB"比"1 MB"更有信息量；
  // 大于 10 时整数就够了，"23.4 MB"里的 0.4 没人关心。
  final text = value < 10 ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
  return '$text ${units[unit]}';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

/// 收一个字符串数组，顺手把空串与非字符串条目剔掉。
///
/// 宽容是有意的：清单是生成脚本写的、但也会被人手工改（加个镜像、试个新源），
/// 不该因为多写了一个空串就让整份清单作废。
List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final result = <String>[];
  for (final item in value) {
    final text = _asString(item);
    if (text != null) {
      result.add(text.trim());
    }
  }
  return result.where((item) => item.isNotEmpty).toList();
}

DateTime? _asDateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
