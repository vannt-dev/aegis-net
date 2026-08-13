/// The app's marketing version, shown in the UI.
///
/// This has to be kept in step with `version:` in `pubspec.yaml` by hand — the
/// app has no `package_info_plus` dependency, and adding a platform plugin
/// purely to render a string in the footer is not worth it across six targets.
///
/// Drift is prevented by `app version constant matches pubspec.yaml` in
/// `test/unit_test.dart`, which the release workflow runs before it will build
/// anything. The footer used to hardcode "v1.0.0" with nothing checking it.
const String kAppVersion = '1.2.0';
