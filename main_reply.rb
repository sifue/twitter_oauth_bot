# Twitter Bot スクリプト(返信用)
# 自分宛返信優先で、XMLの上部から最初にヒットしたキーワードのポストを返信。
# 一度返信したポストには二度返信はしない。
#
# ・自分宛のメッセージを解析して返信を行う
# ・ポスト解析して返信を行う
# ・(コメントアウト)自分宛のメッセージをお気に入りに登録する
#
# 2010/01/24
# Copyright(c) 2009- Soichiro YOSHIMURA

Dir::chdir(File::dirname(__FILE__))
require 'twitter_bot.rb'

bot = TwitterBot.new('conf.yml')

puts 'replied_post_for_me_ids:'
replied_comment_ids = bot.reply_for_me('reply_for_me.xml')
p replied_comment_ids

puts 'replied_post_ids:'
p bot.reply('reply.xml', replied_comment_ids, true) - replied_comment_ids
 
#puts 'favorite_ids:'
#p bot.favorite(replied_comment_ids)

puts 'finished.'
exit(0)