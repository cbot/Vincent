Pod::Spec.new do |s|
  s.name         = 'Vincent'
  s.version      = '1.5.3'
  s.summary      = 'A small library that makes it easy to download and display remote images.'
  s.homepage     = 'https://github.com/cbot/Vincent'
  s.license      = 'MIT'
  s.author       = { 'Kai Straßmann' => 'derkai@gmail.com' }
  
  s.platforms    = { "ios" => "9.0" }

  s.source       = { :git => 'https://github.com/cbot/Vincent.git', :tag => s.version.to_s }
  s.source_files  = 'Classes/*'
  s.dependency 'CryptoSwift', '~> 0.6.6'
  s.dependency 'AsyncImageCache', '~> 1.0.1'
end
