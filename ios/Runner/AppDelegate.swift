import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Runs when the implicit engine is created. The com.aegisnet/vpn channel is
  /// wired here rather than in didFinishLaunchingWithOptions: under the UIScene
  /// lifecycle no scene has connected yet at launch, so `window` — and with it
  /// the FlutterViewController — is still nil at that point and the channel
  /// would silently never be registered.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AegisVpnManager") {
      VpnManager.shared.register(with: registrar.messenger())
    }
  }
}
