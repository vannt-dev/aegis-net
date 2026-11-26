/// Which networks protection applies on (Android). Off by default: every
/// network. On a network left out the tunnel stays up without filtering and
/// filters again by itself on the next network that is in.
enum NetworkScope {
  all('all'),
  wifiOnly('wifi'),
  mobileOnly('mobile');

  const NetworkScope(this.stored);

  /// The value kept in preferences, which the Android service reads too.
  final String stored;

  /// An unknown value (one from a newer version) means every network, so
  /// a setting the app cannot read never costs protection.
  static NetworkScope fromStored(String? value) => NetworkScope.values
      .firstWhere((s) => s.stored == value, orElse: () => NetworkScope.all);
}

/// Preference keys. The Android service reads them under the "flutter."
/// prefix (see NetworkRule.kt), so they must not be renamed.
const String prefNetworkScope = 'network_rule_mode';
const String prefSsidExceptionsOn = 'network_ssid_exceptions_on';

/// One Wi-Fi name per line, a plain string the service can read.
const String prefSsidExceptions = 'network_ssid_exceptions';

/// The Wi-Fi names as kept in preferences.
String encodeSsids(Iterable<String> names) => names.join('\n');

List<String> decodeSsids(String? stored) => (stored ?? '')
    .split('\n')
    .where((n) => n.trim().isNotEmpty)
    .toSet()
    .toList();

/// A Wi-Fi name typed or read, ready to be listed, or null when it cannot be
/// one: empty, longer than the 32 bytes a Wi-Fi name has, or with a line
/// break, which the stored list uses between names. A typed name is trimmed;
/// one read from the device ([exact]) is kept as it is, spaces included.
String? cleanSsid(String input, {bool exact = false}) {
  final name = exact ? input : input.trim();
  if (name.isEmpty || name.contains('\n') || name.contains('\r')) return null;
  if (_utf8Length(name) > 32) return null;
  return name;
}

int _utf8Length(String s) {
  var bytes = 0;
  for (final rune in s.runes) {
    bytes += rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
  }
  return bytes;
}

/// What the app may do with location, which reading the name of the Wi-Fi
/// network takes on Android.
class LocationAccess {
  /// Location access while the app is in use.
  final bool granted;

  /// "Allow all the time": the name can be read with the app closed.
  final bool background;

  /// The device's location switch; null when unknown.
  final bool? locationOn;

  /// Android version; 0 when unknown (not Android, or no answer).
  final int sdkInt;

  const LocationAccess({
    required this.granted,
    required this.background,
    required this.locationOn,
    required this.sdkInt,
  });

  static const unknown = LocationAccess(
      granted: false, background: false, locationOn: null, sdkInt: 0);

  factory LocationAccess.fromMap(Map<String, dynamic> map) => LocationAccess(
        granted: map['fine'] == true,
        background: map['background'] == true,
        locationOn: map['locationOn'] as bool?,
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      );

  /// Android 10+ hides the name from a closed app without "all the time".
  bool get needsBackground => granted && !background && sdkInt >= 29;
}
