Pod::Spec.new do |s|
  s.name           = 'VitalsTailnet'
  s.version        = '1.0.0'
  s.summary        = 'Embedded Tailscale node for Vitals Remote'
  s.author         = 'Vitals'
  s.homepage       = 'https://vitals.rafay99.com'
  s.license        = 'MIT'
  s.platforms      = { :ios => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.vendored_frameworks = 'Tailnet.xcframework'
  s.source_files = '*.swift'
end
