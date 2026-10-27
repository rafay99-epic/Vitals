Pod::Spec.new do |s|
  s.name           = 'VitalsShare'
  s.version        = '1.0.0'
  s.summary        = 'Shares this iPhone\'s photos and picked folders with Vitals, and draws PDF previews'
  s.author         = 'Vitals'
  s.homepage       = 'https://vitals.rafay99.com'
  s.license        = 'GPL-3.0'
  s.platforms      = { :ios => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'Photos', 'AVFoundation', 'ImageIO', 'UniformTypeIdentifiers', 'PDFKit'
  s.source_files = '*.swift'
end
