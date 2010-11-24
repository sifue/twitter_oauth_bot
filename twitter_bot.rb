require 'yaml'
require 'rubygems'
require 'twitter'
require "time"

# Twitter Botの機能を集約したクラス
#   ・ひとりごとをつぶやく
#   ・フォローしている人をフォローし返す
#   ・新たにフォローしてくれた人にウェルカムポストをする
#   ・フォローを外した人をフォロー解除する
#   ・ポスト解析して返信を行うとぃ
#   ・自分宛のメッセージを解析して返信を行う
#   ・特定のメッセージをお気に入りにする
#
# なおすべてのメッセージは、
#   ・#user_name#をユーザー名
#   ・#date#を今日の◯月◯日に
#   ・#time#を今の◯時◯分に
# それぞれ置換されたメッセージをポストする
#
# 2009/09/23, updated 2010/01/03
# Copyright(c) 2009- Soichiro YOSHIMURA

class TwitterBot

  public
  def initialize(conf_file)
    @conf = YAML::load(File.read(conf_file))
    @client = create_client
  end
  
  # ひとりごとをポスト
  # メッセージのXMLの形式は以下の通り
  #
  # <?xml version='1.0' encoding='UTF-8'?>
  # <post>
  #   <comment last_time='1262509457' count='22' content='メッセージ'/>
  # </post>
  #
  def post(xml_file)
    doc_post = REXML::Document.new(File.read(xml_file))
    comments = doc_post.root().get_elements('comment')

    comment = nil
    if @conf['bot']['post_random']
      comment = comments[rand(comments.length)]
    else
      comment = most_unused_comment(comments)
    end

    message = replace_token(comment, '')
    @client.update(Kconv.kconv(message,
      Kconv::UTF8))

    update_comment_attr(comment)
    save_xml(doc_post, xml_file)
    
    comment
  end

  # 新しいfollowerをフォロー返し、追加したidの配列を返す
  def follow_new_followers
    follower_names = []
    @client.follower_ids.each { |id| follower_names << id }
    friend_names = []
    @client.friend_ids.each { |id| friend_names << id}
    add_followers = follower_names - friend_names

    added_followers = []
    add_followers.each { |id|
      begin
        @client.friendship_create(id)
        added_followers << id
      rescue => ex
        print ex.message, "\n"
      end
     }
    added_followers
  end

  # 自分をフォローしていないをフォロワーを解除し、解除したidを返す
  def unfollow_new_unfollowers
    follower_names = []
    @client.follower_ids.each { |id| follower_names << id }
    friend_names = []
    @client.friend_ids.each { |id| friend_names << id}
    delete_unfollowers = friend_names - follower_names

    deleted_unfollowers = []
    delete_unfollowers.each { |id|
      begin
        @client.friendship_destroy(id)
        deleted_unfollowers << id
      rescue => ex
        print ex.message, "\n"
      end
     }
    deleted_unfollowers
  end

  # 指定したidのユーザーにウェルカムポストを投稿
  # メッセージのXMLの形式は以下の通り。#user_name#をユーザー名と置換
  #
  # <?xml version='1.0' encoding='UTF-8'?>
  # <post>
  #   <comment last_time='1262509457' count='22' content='#user_name#さん、メッセージ'/>
  # </post>
  #
  def welcome(ids, xml_file)

    posted_welcome_comments = []
    return posted_welcome_comments if ids.size == 0

    doc_post = REXML::Document.new(File.read(xml_file))
    comments = doc_post.root().get_elements('comment')

    ids.each { |id|
      comment = nil
      if @conf['bot']['post_random']
        comment = comments[rand(comments.length)]
      else
        comment = most_unused_comment(comments)
      end

      name_replaced_message = replace_token(comment, @client.user(id).name)

      # ポスト！
      @client.update(Kconv.kconv( "@" + @client.user(id).screen_name +
            " " + name_replaced_message,
         Kconv::UTF8 ))

      update_comment_attr(comment)

      posted_welcome_comments << comment
    }

    save_xml(doc_post, xml_file)

    posted_welcome_comments
  end

  # 指定された時間内のポスト解析をして、引っかかるキーワードがあれば返信、
  # 返信したポストのIDの配列を返す
  # メッセージのXMLの形式は以下の通り。#user_name#をユーザー名と置換
  #
  #<?xml version='1.0' encoding='UTF-8'?>
  #<reply>
  #    <keyword term='アイシャ'>
  #        <comment last_time='1262510469' content='ありがとう！#user_name#も頑張ってね！' count='7'/>
  #        <comment last_time='1262498652' content='わたしも頑張るね！#user_name#も頑張ってね！' count='6'/>
  #    </keyword>
  #</reply>
  #
  def reply(xml_file, replied_comment_ids=[], isUseCache=false)
    reply_internal(xml_file, false, replied_comment_ids, isUseCache)
  end

  # 自分宛のポスト解析をして、引っかかるキーワードがあれば返信、
  # 返信したポストのIDの配列を返す
  # メッセージのXMLの形式は以下の通り。#user_name#をユーザー名と置換
  #
  # キャッシュを使うと設定だと、reply系を繰り返すとき新規に情報を取得しませんが
  # リクエスト数を減らすことができます。(twitterの1時間150リクエストの制限)
  #
  #<?xml version='1.0' encoding='UTF-8'?>
  #<reply>
  #    <keyword term='アイシャ'>
  #        <comment last_time='1262510469' content='ありがとう！#user_name#も頑張ってね！' count='7'/>
  #        <comment last_time='1262498652' content='わたしも頑張るね！#user_name#も頑張ってね！' count='6'/>
  #    </keyword>
  #</reply>
  #
  def reply_for_me(xml_file, replied_comment_ids=[], isUseCache=false)
    reply_internal(xml_file, true, replied_comment_ids, isUseCache)
  end

  # 渡されたidの配列のポストをすべてお気に入りににする
  def favorite(ids)
    ids.each{|id|
      begin
        @client.favorite_create(id)
      rescue => ex
        print ex.message, "\n"
      end
      }
    ids
  end

  private
  # twitterクライアントの作成
  def create_client
    oauth_bot_conf = @conf['bot']['oauth']
    oauth = Twitter::OAuth.new(
      oauth_bot_conf['consumer_key'],
      oauth_bot_conf['consumer_secret']
      )
    oauth.authorize_from_access(
      oauth_bot_conf['token'],
      oauth_bot_conf['secret']
    )
    Twitter::Base.new(oauth)
  end

  # comment要素配列の中で最も古くてポスト回数が少ないものを取得
  def most_unused_comment(comments)
      # コメント配列をポスト回数・日付順に破壊的ソート
      comments.sort! { |a,b|
        a.attributes.get_attribute('last_time').to_s.to_i <=>
          b.attributes.get_attribute('last_time').to_s.to_i
      }.sort! { |a,b|
        a.attributes.get_attribute('count').to_s.to_i <=>
          b.attributes.get_attribute('count').to_s.to_i
      }
      comments[0]
  end

  # comment要素の更新日時とカウントを更新
  def update_comment_attr(comment)
    count = comment.attributes.get_attribute('count').to_s.to_i + 1
    comment.delete_attribute('count')
    comment.add_attribute('count', count.to_s)
    comment.delete_attribute('last_time')
    comment.add_attribute('last_time', Time.now.to_i.to_s)
    comment
  end

  # ファイルにxmlのdomを保存する
  def save_xml(doc_post, xml_file)
    io = open(xml_file,'w')
    doc_post.write(io)
    io.close
  end
  
  # ・#user_name#をユーザー名
  # ・#date#を今日の◯月◯日に
  # ・#time#を今の◯時◯分に
  # それぞれ置換されたメッセージを取得する
  def replace_token(comment, user_name)
    name_replaced_message = comment.attributes.get_attribute('content').to_s
    name_replaced_message = name_replaced_message.gsub(/#user_name#/, user_name)
    today = Time.now
    name_replaced_message =
      name_replaced_message.gsub(/#date#/,
      today.month.to_s + "月" + today.day.to_s + "日")
    name_replaced_message =
      name_replaced_message.gsub(/#time#/,
      today.hour.to_s + "時" + today.min.to_s + "分")
    name_replaced_message
  end

  # xmlから返信する処理を行う処理の内部実装
  def reply_internal(xml_file, is_for_me, replied_comment_ids, isUseCache)
    replied_comment_ids = replied_comment_ids.dup
    doc_rep = nil

    # キャッシュを使わないなら必ずリクエスト、使う設定でも変数がnilならリクエスト
    @friends_timeline = @client.friends_timeline if !isUseCache || @friends_timeline == nil

    @friends_timeline.each{|mash|

      if is_for_me
        # もし自分あての返信でなければパス
        reg = Regexp.new("^@" + @conf['bot']['login'])
        next if reg.match(mash.text) == nil
      end

      # インターバル時間より前のコメントはパス
      next if Time.parse(mash.created_at) < Time.at(Time.now.to_i - @conf['bot']['interval'])
      # 自分の投稿はパス
      next if mash.user.screen_name == @conf['bot']['login']

      doc_rep = REXML::Document.new(File.read(xml_file)) if doc_rep == nil

      doc_rep.root.elements.each{|k|

        # 既に返信済のポストはパス
        next if replied_comment_ids.include?(mash.id)

        term = k.attributes.get_attribute('term').to_s
        # 一つ一つのキーワードに関して、そのキーワードを含んでいるか
        next if !mash.text.include?(term)

        comments = k.get_elements('comment')
        comment = nil
        if @conf['bot']['post_random']
         comment = comments[rand(comments.length)]
        else
         comment = most_unused_comment(comments)
        end

        name_replaced_message = replace_token(comment, mash.user.name)
        @client.update(Kconv.kconv(
            "@" + mash.user.screen_name + " " + name_replaced_message,
            Kconv::UTF8 ),
        {:in_reply_to_status_id => mash.id })

        update_comment_attr(comment)
        replied_comment_ids << mash.id
      }
    }

    save_xml(doc_rep, xml_file) if doc_rep != nil
    replied_comment_ids
  end
end
