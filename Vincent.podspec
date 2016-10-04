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
  s.dependency 'CryptoSwift', '~> 0.6.0'
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '3.0'}
end
