import 'dart:convert';

import 'package:flutter/services.dart';

class ProviderLogoCatalog {
  ProviderLogoCatalog._();

  ProviderLogoCatalog.fromData({
    required Map<String, String> mapping,
    required Iterable<String> assetPaths,
    Map<String, String> overrides = const {},
  }) {
    _replaceData(
      mapping: mapping,
      assetPaths: assetPaths,
      overrides: overrides,
    );
  }

  static final ProviderLogoCatalog instance = ProviderLogoCatalog._();

  static const mappingAssetPath = 'assets/data/authenticator_logo_map.json';
  static const overridesAssetPath =
      'assets/data/authenticator_logo_overrides.json';
  static const logoAssetDirectory = 'assets/logos/authenticators/';

  Map<String, String> _logoNameByIssuer = const {};
  Map<String, String> _assetPathByNormalizedStem = const {};
  Map<String, String> _logoNameOverrides = const {};

  bool get isLoaded => _assetPathByNormalizedStem.isNotEmpty;

  Future<void> load({AssetBundle? bundle}) async {
    final selectedBundle = bundle ?? rootBundle;
    final rawMapping = await selectedBundle.loadString(mappingAssetPath);
    final rawOverrides = await selectedBundle.loadString(overridesAssetPath);
    final manifest = await AssetManifest.loadFromAssetBundle(selectedBundle);

    final mapping = _decodeStringMap(rawMapping, mappingAssetPath);
    final overrides = _decodeStringMap(rawOverrides, overridesAssetPath);
    final assetPaths = manifest.listAssets().where(
      (path) => path.startsWith(logoAssetDirectory) && path.endsWith('.png'),
    );

    _replaceData(
      mapping: mapping,
      assetPaths: assetPaths,
      overrides: overrides,
    );
  }

  /// Logo chỉ là enhancement; catalog lỗi không được chặn local TOTP bootstrap.
  Future<void> loadBestEffort({AssetBundle? bundle}) async {
    try {
      await load(bundle: bundle);
    } on Object {
      _logoNameByIssuer = const {};
      _assetPathByNormalizedStem = const {};
      _logoNameOverrides = const {};
    }
  }

  String? logoAssetForIssuer(String issuer) {
    for (final candidate in _candidateIssuerKeys(issuer)) {
      final mappedName = _logoNameByIssuer[candidate];
      if (mappedName == null) continue;
      final correctedName =
          _logoNameOverrides[mappedName.toLowerCase()] ?? mappedName;
      final assetPath = _assetPathByNormalizedStem[correctedName.toLowerCase()];
      if (assetPath != null) return assetPath;
    }
    return null;
  }

  void _replaceData({
    required Map<String, String> mapping,
    required Iterable<String> assetPaths,
    required Map<String, String> overrides,
  }) {
    final normalizedMapping = <String, String>{};
    for (final entry in mapping.entries) {
      final issuer = entry.key.trim().toLowerCase();
      final logoName = entry.value.trim();
      if (issuer.isEmpty || logoName.isEmpty) {
        throw const FormatException('Provider logo mapping chứa giá trị rỗng.');
      }
      normalizedMapping[issuer] = logoName;
    }

    final normalizedAssets = <String, String>{};
    for (final path in assetPaths) {
      if (!path.startsWith(logoAssetDirectory) || !path.endsWith('.png')) {
        continue;
      }
      final filename = path.substring(path.lastIndexOf('/') + 1);
      final normalizedStem = filename
          .substring(0, filename.length - '.png'.length)
          .toLowerCase();
      final previous = normalizedAssets[normalizedStem];
      if (previous != null && previous != path) {
        throw FormatException(
          'Provider logo asset trùng tên không phân biệt hoa thường.',
        );
      }
      normalizedAssets[normalizedStem] = path;
    }
    if (normalizedAssets.isEmpty) {
      throw const FormatException('Provider logo catalog không có asset PNG.');
    }

    _logoNameByIssuer = Map.unmodifiable(normalizedMapping);
    _assetPathByNormalizedStem = Map.unmodifiable(normalizedAssets);
    _logoNameOverrides = Map.unmodifiable(
      overrides.map(
        (key, value) =>
            MapEntry(key.trim().toLowerCase(), value.trim().toLowerCase()),
      ),
    );
  }

  static Map<String, String> _decodeStringMap(String raw, String source) {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$source phải là JSON object.');
    }
    return decoded.map((key, value) {
      if (value is! String) {
        throw FormatException('$source chỉ được chứa string value.');
      }
      return MapEntry(key, value);
    });
  }

  static Iterable<String> _candidateIssuerKeys(String issuer) {
    final normalized = issuer.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final candidates = <String>{normalized};
    final withoutDotCom = normalized.replaceAll('.com', '').trim();
    if (withoutDotCom.isNotEmpty) candidates.add(withoutDotCom);

    for (final value in List<String>.of(candidates)) {
      final firstWord = value.split(RegExp(r'\s+')).first;
      if (firstWord.isNotEmpty) candidates.add(firstWord);
    }
    return candidates;
  }
}
