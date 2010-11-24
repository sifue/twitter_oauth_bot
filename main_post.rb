# Twitter Bot (つぶやきとウェルカムメッセージ用)
#
# ・フォローしている人をフォローし返す
# ・新たにフォローしてくれた人にウェルカムポストをする
# ・(コメントアウト)フォローを外した人をフォロー解除する
# ・通常のつぶやきを行う
# 
# 2010/01/24
# Copyright(c) 2010- Soichiro YOSHIMURA

Dir::chdir(File::dirname(__FILE__))
require 'twitter_bot.rb'

bot = TwitterBot.new('conf.yml')

puts 'add_follower_ids:'
add_follower_ids = bot.follow_new_followers
p add_follower_ids

puts 'posted_welcome_comments:'
p bot.welcome(add_follower_ids, 'welcome.xml')

#puts 'delete_follower_ids:'
#p bot.unfollow_new_unfollowers

puts "posted:"
p bot.post('post.xml')

puts 'finished.'
exit(0)