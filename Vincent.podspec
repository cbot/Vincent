Pod::Spec.new do |s|
  s.name         = 'Vincent'
  s.version      = '1.5.0'
  s.summary      = 'A small library that makes it easy to download and display remote images.'
  s.homepage     = 'https://github.com/cbot/Vincent'
  s.license      = 'MIT'
  s.author       = { 'Kai Straßmann' => 'derkai@gmail.com' }
  
  s.platforms    = { "ios" => "8.0" }

  s.source       = { :git => 'https://github.com/cbot/Vincent.git', :tag => s.version.to_s }
  s.source_files  = 'Classes/*'
  
  # Ensure module isn't deleted by CocoaPods
  s.preserve_paths = 'Vincent/CommonCrypto/*'
  s.pod_target_xcconfig = { 'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/Vincent/CommonCrypto' }
  s.user_target_xcconfig = { 'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/Vincent/CommonCrypto' }
end
