import 'dart:io';

const requiredDocuments = <String>[
  'AGENTS.md',
  'CONTRIBUTING.md',
  'README.md',
  'privacy_policy.md',
  'docs/README.md',
  'docs/PROJECT_STATUS.md',
  'docs/SYSTEM_DESIGN.md',
  'docs/ARCHITECTURAL_DECISIONS.md',
  'docs/DATA_MODELS.md',
  'docs/SECURITY.md',
  'docs/SUPABASE_INTEGRATION.md',
  'docs/E2EE_DESIGN.md',
  'docs/DEVELOPMENT.md',
  'docs/TESTING_STRATEGY.md',
  'docs/DEPLOYMENT.md',
  'docs/NON_FUNCTIONAL_REQUIREMENTS.md',
  'docs/ROADMAP.md',
  'docs/AI_AGENT_PLAYBOOK.md',
  'docs/adr/0000-template.md',
  'docs/tasks/TEMPLATE.md',
  'reset-password-web/README.md',
];

const ignoredPathParts = <String>[
  '/.git/',
  '/.claude/',
  '/.codex/',
  '/.dart_tool/',
  '/build/',
  '/ios/Pods/',
  '/macos/Pods/',
];

void main() {
  final root = Directory.current.absolute;
  final failures = <String>[];

  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Hãy chạy kiểm tra này từ thư mục root của repository.');
    exitCode = 64;
    return;
  }

  for (final relativePath in requiredDocuments) {
    if (!File('${root.path}/$relativePath').existsSync()) {
      failures.add('Thiếu tài liệu bắt buộc: $relativePath');
    }
  }

  final markdownFiles =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .where((file) => !ignoredPathParts.any(file.path.contains))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  for (final file in markdownFiles) {
    final relativePath = _relativeToRoot(root, file);
    if (relativePath.endsWith('.ru.md') ||
        relativePath.endsWith('.vi.md') ||
        relativePath == 'README.ru.md' ||
        relativePath == 'README.vi.md') {
      failures.add(
        'Tài liệu phải dùng tên file canonical, không dùng hậu tố ngôn ngữ: '
        '$relativePath',
      );
    }

    final content = file.readAsStringSync();
    _checkLinks(root, file, content, failures);
    _checkCredentialLikeContent(relativePath, content, failures);
  }

  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('LỖI $failure');
    }
    stderr.writeln(
      'Documentation gate thất bại với ${failures.length} vấn đề.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Documentation gate đã pass: đã kiểm tra '
    '${markdownFiles.length} file Markdown.',
  );
}

void _checkLinks(
  Directory root,
  File source,
  String content,
  List<String> failures,
) {
  final markdownLink = RegExp(r'\[[^\]]+\]\(([^)]+)\)');
  for (final match in markdownLink.allMatches(content)) {
    final rawTarget = match.group(1)!.trim();
    if (rawTarget.isEmpty ||
        rawTarget.startsWith('#') ||
        rawTarget.startsWith('http://') ||
        rawTarget.startsWith('https://') ||
        rawTarget.startsWith('mailto:')) {
      continue;
    }

    final withoutAnchor = rawTarget.split('#').first;
    if (withoutAnchor.isEmpty || withoutAnchor.startsWith('/')) {
      continue;
    }

    final resolved = File(
      '${source.parent.path}/${Uri.decodeComponent(withoutAnchor)}',
    ).absolute;
    if (!resolved.existsSync()) {
      failures.add(
        'Link hỏng trong ${_relativeToRoot(root, source)}: $rawTarget',
      );
    }
  }
}

void _checkCredentialLikeContent(
  String path,
  String content,
  List<String> failures,
) {
  final jwtLike = RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}');
  if (jwtLike.hasMatch(content)) {
    failures.add('Phát hiện giá trị giống JWT trong $path');
  }

  final unsafeOtpUri = RegExp(
    r'otpauth://[^\s)]*secret=(?!REDACTED|TEST_ONLY)[A-Za-z2-7]{8,}',
    caseSensitive: false,
  );
  if (unsafeOtpUri.hasMatch(content)) {
    failures.add('Phát hiện URI otpauth giống credential trong $path');
  }
}

String _relativeToRoot(Directory root, File file) {
  final prefix = '${root.path}/';
  return file.absolute.path.startsWith(prefix)
      ? file.absolute.path.substring(prefix.length)
      : file.path;
}
