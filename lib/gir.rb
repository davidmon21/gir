require 'base64'
require 'rbnacl'
require 'io/console'
require 'rubygems'

%w[ utils girtui notebook ].each do |file|
 require "gir/#{file}"
end
