# 登録したアプリケーションの許可を行います
#
# 2010/01/24
# Copyright(c) 2010- Soichiro YOSHIMURA

Dir::chdir(File::dirname(__FILE__))
require 'yaml'
require 'rubygems'
require 'oauth'

conf_file = 'conf.yml'
conf = YAML::load(File.read(conf_file))
bot_conf = conf['bot']
oauth_bot_conf = bot_conf['oauth']

consumer = OAuth::Consumer.new(
  oauth_bot_conf['consumer_key'],
  oauth_bot_conf['consumer_secret'],
  :site => 'http://twitter.com'
)

request_token = consumer.get_request_token

puts "以下のURLにアクセスしてアプリケーションを許可し、暗証番号を入力してください\n" +
  request_token.authorize_url
print '>'

oauth_verifier = gets.chomp!.to_i
access_token = request_token.get_access_token(
  :oauth_verifier => oauth_verifier
)

oauth_bot_conf['token'] = access_token.token
oauth_bot_conf['secret'] = access_token.secret

# conf_fileにtokenとsecretが保存
yaml_map = conf.to_yaml
io_w = File.open(conf_file,'w')
yaml_map.each_line{|line|
  io_w.puts(line)
}
io_w.close

puts "アプリケーションが許可され、#{conf_file}にtokenとsecretが保存されました。"