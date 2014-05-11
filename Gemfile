source 'https://rubygems.org'

require 'rbconfig'

def windows_only(require_as)
  RbConfig::CONFIG['host_os'] =~ /mingw|mswin/i ? require_as : false
end

def linux_only(require_as)
  RbConfig::CONFIG['host_os'] =~ /linux/ ? require_as : false
end

def darwin_only(require_as)
  RbConfig::CONFIG['host_os'] =~ /darwin/ ? require_as : false
end

gem 'aws-sdk'
gem 'clipboard'
gem 'filesize'
gem 'listen', '~> 2.0', :github => 'guard/listen'
gem 'rb-fsevent', :require => darwin_only('rb-fsevent')
gem 'rb-inotify', :require => linux_only('rb-inotify')
gem 'terminal-notifier', :require => darwin_only('terminal-notifier')
gem 'thor'
gem 'wdm', "~> 0.1.0", :platforms => [:mswin, :mingw], :require => windows_only('wdm')
