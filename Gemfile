source 'https://rubygems.org'

require 'rbconfig'

gem 'aws-sdk'
gem 'clipboard'
gem 'listen', '~> 2.0', github: 'guard/listen'
gem 'rb-fsevent'
gem 'rb-inotify'
gem 'thor'

windows = RbConfig::CONFIG['target_os'] =~ /mswin|mingw|cygwin/i
gem 'wdm', '>= 0.1.0' if windows
