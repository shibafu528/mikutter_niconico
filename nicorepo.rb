# -*- coding: utf-8 -*-
require 'mechanize'

module NicoRepo
    FROM_UNKNOWN = 0
    FROM_USER = 1
    FROM_COMMUNITY = 2

    # ユーザーのニコレポ
    ## マイリスト/クリップ追加
    MYLIST_ADD = "log-user-mylist-add"
    IMAGE_CLIP = "log-user-seiga-image-clip"
    ## 宣伝
    ADVERTISE = "log-user-uad-advertise"
    ## ニコ生開始
    LIVE_BROADCAST = "log-user-live-broadcast"
    ## 動画/静画/ブロマガの投稿
    VIDEO_UPLOAD = "log-user-video-upload"
    IMAGE_UPLOAD = "log-user-seiga-image-upload"
    REGISTER_CHBLOG = "log-user-register-chblog"
    ## 動画再生数のキリ番
    VIDEO_KIRIBAN = "log-user-video-round-number-of-view-counter"

    # チャンネル&コミュニティのニコレポ
    ## ニコ生開始
    CO_LIVE_BROADCAST = "log-community-live-broadcast"
    ## ニコ生予約
    CO_LIVE_RESERVE = "log-community-live-reserve"
    ## コミュニティ動画の追加
    CO_VIDEO_UPLOAD = "log-community-video-upload"
    ## お知らせの投稿
    CO_ACTION_INFO = "log-community-action-info"

    class NicoRepoLog
        def initialize(element)
            # レポートの種類を取得
            @report_type = element["class"].gsub(/^log /,"")
            if @report_type.include?("log-user") then
                @report_from = FROM_USER
            elsif @report_type.include?("log-community") then
                @report_from = FROM_COMMUNITY
            else
                @report_from = FROM_UNKNOWN
            end

            element.children.each {|log_elem|
                if log_elem["class"] == "log-author " then
                    # ニコレポの発生源を取得
                    author_elem = log_elem.at("a")
                    @author_url = author_elem.get_attribute("href")
                    @author_image_url = author_elem.at("img").get_attribute("data-src")
                elsif log_elem["class"] == "log-content" then
                    body_elem = log_elem.at("div.log-body")

                    # ニコレポの本文を取得
                    @content_body = body_elem.text.gsub(/(\r|\n|\t)/,"")

                    # ニコレポの発生源の名前を取得
                    body_elem.children.each {|e|
                        if e["class"].to_s.include?("author-") then
                            @author_name = e.text
                        end
                    }
                    if @author_name.nil? && /^(.+) さんが.*/ =~ @content_body then
                        @author_name = @content_body.scan(/^(.+) さんが.*/)[0][0]
                    end

                    # ニコレポにリンクされているコンテンツについての情報を取得
                    details_elem = log_elem.at("div.log-details")
                    begin
                    @target_thumb = details_elem.at("div.log-target-thumbnail").at("a").at("img").get_attribute("data-src")
                    rescue; end
                    begin 
                    target_elem = details_elem.at("div.log-target-info").at("a")
                    @target_url = target_elem["href"]
                    @target_title = target_elem.inner_text
                    rescue; end
                    # ニコレポの日時を取得
                    date_elem = details_elem.at("div.log-footer").at("div.log-footer-inner").at("a.log-footer-date").at("time")
                    @date = Time::parse(date_elem["datetime"])
                    @date_str = date_elem.text.gsub(/(\r|\n|\t)/,"")
                end
            }
        end

        attr_reader :report_from, :report_type
        attr_reader :author_url, :author_name, :author_image_url
        attr_reader :content_body
        attr_reader :target_thumb, :target_url, :target_type, :target_title
        attr_reader :date, :date_str
    end

    class NotLoginException < StandardError; end

    class NicoRepoReader
        def initialize()
            @agent = Mechanize.new
            @agent.ssl_version = "SSLv3"
            @agent.request_headers = {"Accept-Language"=>"ja"}
        end

        def login(mail, password)
            @agent.post("https://secure.nicovideo.jp/secure/login?site=niconico","mail"=>mail,"password"=>password)
        end

        def get()
            @agent.get("http://www.nicovideo.jp/my/top/all")
            if @agent.page.title.include?("ログイン") then
                raise NotLoginException, "ニコニコ動画にログインしていません."
            end
            elements = @agent.page.search("div.log")
            reports = Array.new
            i = 0
            elements.each {|e|
                n = NicoRepo::NicoRepoLog.new(e)
                reports[i] = n
                i += 1
            }
            return reports
        end
    end
end 
