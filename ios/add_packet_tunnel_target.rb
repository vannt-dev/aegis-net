#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Adds the PacketTunnel Network Extension target to ios/Runner.xcodeproj.
#
# The extension's source, Info.plist, entitlements and bridging header have all
# been in the repo for a while, but no target ever referenced them — so
# PacketTunnelProvider.swift has never been compiled, and VpnManager's
# providerBundleIdentifier pointed at a bundle that does not exist.
#
# This is a script rather than a hand-edit of project.pbxproj because that file
# is a graph of ~15 interlinked objects with generated UUIDs; getting one
# reference wrong corrupts the project in ways Xcode reports unhelpfully.
#
# Usage (macOS):
#   gem install xcodeproj
#   ruby ios/add_packet_tunnel_target.rb
#
# Idempotent: running it twice is a no-op. What it cannot do is pick your
# signing Team or create App IDs in the developer portal — see ios/IOS_SETUP.md
# for those steps.

require 'xcodeproj'

PROJECT_PATH   = File.expand_path('Runner.xcodeproj', __dir__)
TARGET_NAME    = 'PacketTunnel'
APP_TARGET     = 'Runner'
APP_BUNDLE_ID  = 'com.aegisnet.app'
BUNDLE_ID      = "#{APP_BUNDLE_ID}.#{TARGET_NAME}"
DEPLOYMENT     = '13.0'

abort "Not found: #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "✅ #{TARGET_NAME} target already present — nothing to do."
  exit 0
end

app_target = project.targets.find { |t| t.name == APP_TARGET }
abort "Could not find the #{APP_TARGET} target" if app_target.nil?

# 1. The extension target itself.
extension_target = project.new_target(
  :app_extension,
  TARGET_NAME,
  :ios,
  DEPLOYMENT
)

# 2. Source files. The group is created with a path so Xcode shows the files
#    where they actually live rather than as loose references.
group = project.main_group.find_subpath(TARGET_NAME, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(TARGET_NAME)

%w[PacketTunnelProvider.swift].each do |name|
  path = File.join(__dir__, TARGET_NAME, name)
  abort "Missing source file: #{path}" unless File.exist?(path)
  extension_target.add_file_references([group.new_reference(name)])
end

# Info.plist, entitlements and the bridging header are referenced by build
# setting, not compiled — but list them so they are visible in Xcode.
%w[Info.plist PacketTunnel.entitlements PacketTunnel-Bridging-Header.h].each do |name|
  group.new_reference(name) unless group.files.any? { |f| f.display_name == name }
end

# 3. Build settings.
extension_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'    => BUNDLE_ID,
    'PRODUCT_NAME'                 => '$(TARGET_NAME)',
    'INFOPLIST_FILE'               => "#{TARGET_NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'       => "#{TARGET_NAME}/#{TARGET_NAME}.entitlements",
    'SWIFT_OBJC_BRIDGING_HEADER'   => "#{TARGET_NAME}/#{TARGET_NAME}-Bridging-Header.h",
    'SWIFT_VERSION'                => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET'   => DEPLOYMENT,
    'CODE_SIGN_STYLE'              => 'Automatic',
    # An app extension is packaged inside the host app, never installed on its
    # own; without this the archive step tries to and fails.
    'SKIP_INSTALL'                 => 'YES',
    'TARGETED_DEVICE_FAMILY'       => '1,2'
  )
end

# 4. Make the app build the extension and embed it in PlugIns/.
app_target.add_dependency(extension_target)

embed_phase = app_target.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
    phase.symbol_dst_subfolder_spec == :plug_ins
end

if embed_phase.nil?
  embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
embed_phase.add_file_reference(extension_target.product_reference)

# The extension has to be embedded before the app is signed.
app_target.build_phases.delete(embed_phase)
app_target.build_phases.insert(-1, embed_phase)

# 5. Link the Rust engine into BOTH targets when it has been built.
#
#    Runner needs it too, and it is the easy one to forget: on iOS the Dart
#    side loads the engine with DynamicLibrary.process(), which only finds
#    symbols already linked into the running binary. Link it into the extension
#    alone and every lookup throws, AegisBridge._useNativeFfi stays false, and
#    the app quietly runs on placeholder rules while claiming to be protected.
framework_path = File.join(__dir__, 'Frameworks', 'AegisCore.xcframework')
if Dir.exist?(framework_path)
  frameworks_group = project.main_group.find_subpath('Frameworks', true)
  ref = frameworks_group.new_reference('Frameworks/AegisCore.xcframework')

  [extension_target, app_target].each do |target|
    already_linked = target.frameworks_build_phase.files.any? do |f|
      f.display_name == 'AegisCore.xcframework'
    end
    target.frameworks_build_phase.add_file_reference(ref) unless already_linked
  end
  puts '   linked AegisCore.xcframework into Runner and PacketTunnel'
else
  puts "⚠️  #{framework_path} not found — run ./ios/build_rust_ios.sh first,"
  puts '   then re-run this script (or add the xcframework to both targets by hand).'
end

project.save

puts "✅ Added the #{TARGET_NAME} target (#{BUNDLE_ID})."
puts
puts 'Still manual, because they are tied to your developer account:'
puts '  • Select your Team on both targets (Signing & Capabilities).'
puts "  • Create App IDs for #{APP_BUNDLE_ID} and #{BUNDLE_ID} with the"
puts '    Network Extensions and App Groups capabilities enabled.'
