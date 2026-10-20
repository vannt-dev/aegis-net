import '../i18n/app_strings.dart';
import '../services/rule_downloader_service.dart';

/// What the engine says a lookup of [domain] gets, and why.
///
/// [reason] is the engine's name for the cause (`ads`, `custom_rule`,
/// `allowlist`, ...), or null when nothing in particular decided it — or when
/// the engine is too old to say. [list] is the id of the filter list behind
/// it, null for the built-in rules and the user's own lists.
class DomainVerdict {
  final String domain;
  final bool blocked;
  final String? reason;
  final String? list;

  const DomainVerdict({
    required this.domain,
    required this.blocked,
    this.reason,
    this.list,
  });

  factory DomainVerdict.fromJson(Map<String, dynamic> json) => DomainVerdict(
        domain: json['domain']?.toString() ?? '',
        blocked: json['blocked'] == true,
        reason: json['reason'] as String?,
        list: json['list'] as String?,
      );

  /// The sentence to show for this verdict.
  String describe() =>
      describeReason(blocked: blocked, reason: reason, list: list);
}

/// Reasons that name a filter category, which a list may stand behind.
const Set<String> _categoryReasons = {'ads', 'trackers', 'malware', 'adult'};

/// Reasons this version of the app has a sentence for.
const Set<String> _knownReasons = {
  ..._categoryReasons,
  'custom_rule',
  'app',
  'bypass',
  'safesearch',
  'custom_host',
  'allowlist',
  'exception',
};

/// The name to show for a filter list id: its translated name for a preset,
/// what the user called it for their own, or the id itself for a list the
/// app no longer knows.
String listDisplayName(String id) {
  for (final source in RuleDownloaderService.allSources) {
    if (source.id == id) return source.localizedName;
  }
  return id;
}

/// One line saying why a query was blocked, rewritten or let through.
String describeReason({
  required bool blocked,
  String? reason,
  String? list,
}) {
  if (reason == null || !_knownReasons.contains(reason)) {
    return AppStrings.get(blocked ? 'reason_blocked' : 'reason_none');
  }

  final sentence = AppStrings.get('reason_$reason');
  if (_categoryReasons.contains(reason)) {
    final source =
        list == null ? AppStrings.get('reason_builtin') : listDisplayName(list);
    return '$sentence · $source';
  }
  if (reason == 'exception' && list != null) {
    return '$sentence · ${listDisplayName(list)}';
  }
  return sentence;
}

/// Turns what a user typed or pasted — `https://Ads.Example.com/path`,
/// `example.com.`, `example.com:443` — into a bare lowercase domain, or null
/// when what is left is not a domain name.
String? normalizeDomainInput(String input) {
  var value = input.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
  value = value.split(RegExp(r'[/?#]')).first;
  value = value.replaceFirst(RegExp(r':\d+$'), '');
  value = value.replaceFirst(RegExp(r'^\*\.'), '');
  while (value.endsWith('.')) {
    value = value.substring(0, value.length - 1);
  }
  final valid = RegExp(r'^[a-z0-9_]([a-z0-9_\-]*[a-z0-9_])?'
          r'(\.[a-z0-9_]([a-z0-9_\-]*[a-z0-9_])?)*$')
      .hasMatch(value);
  return valid && value.length <= 253 ? value : null;
}
