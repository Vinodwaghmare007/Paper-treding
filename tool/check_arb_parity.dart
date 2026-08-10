// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Fails (exit code 1) if any `lib/l10n/app_<locale>.arb` file is missing a
/// key that `app_en.arb` (the template) has, or has an extra key the
/// template doesn't — `flutter gen-l10n` itself only warns about missing
/// keys and silently ignores extras, so this is the actual gate. Run via:
///   dart run tool/check_arb_parity.dart
/// Wire this into CI (or a pre-commit hook) so a translated ARB file can
/// never silently drift out of sync with app_en.arb as new strings are
/// added.
void main() {
  final l10nDir = Directory('lib/l10n');
  if (!l10nDir.existsSync()) {
    stderr.writeln('lib/l10n/ not found — run this from the project root.');
    exit(2);
  }

  final templateFile = File('lib/l10n/app_en.arb');
  if (!templateFile.existsSync()) {
    stderr.writeln('lib/l10n/app_en.arb (the template) not found.');
    exit(2);
  }

  final templateKeys = _translatableKeys(templateFile);

  final otherFiles = l10nDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (otherFiles.isEmpty) {
    stderr.writeln('No non-English ARB files found under lib/l10n/ to check.');
    exit(2);
  }

  var hasFailure = false;

  for (final file in otherFiles) {
    final keys = _translatableKeys(file);
    final missing = templateKeys.difference(keys);
    final extra = keys.difference(templateKeys);

    if (missing.isEmpty && extra.isEmpty) {
      print('OK    ${file.path} (${keys.length} keys)');
      continue;
    }

    hasFailure = true;
    print('FAIL  ${file.path}');
    if (missing.isNotEmpty) {
      print('      missing ${missing.length} key(s) present in app_en.arb:');
      for (final key in missing.toList()..sort()) {
        print('        - $key');
      }
    }
    if (extra.isNotEmpty) {
      print('      has ${extra.length} extra key(s) not in app_en.arb:');
      for (final key in extra.toList()..sort()) {
        print('        - $key');
      }
    }
  }

  if (hasFailure) {
    stderr.writeln('\nARB key parity check failed — see FAIL lines above.');
    exit(1);
  }
  print('\nAll ${otherFiles.length} translated ARB file(s) match app_en.arb\'s key set.');
}

/// Every top-level key that isn't ARB metadata (`@@locale`,
/// `@@translation_status`) or a per-key description block (`@keyName`) —
/// i.e. the actual translatable strings.
Set<String> _translatableKeys(File file) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}
