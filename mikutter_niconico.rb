# -*- coding: utf-8 -*-
require 'nokogiri'
require 'httpclient'
require 'open-uri'
require_relative 'nicorepo'
require_relative 'model/user'
require_relative 'model/nicorepo'

Plugin.create(:mikutter_niconico) do
    UserConfig[:mikutter_nicorepo_reload_min]   ||= 5
    UserConfig[:mikutter_nicorepo_account_mail] ||= ""
    UserConfig[:mikutter_nicorepo_account_pass] ||= ""

    defactivity "mikutter_niconico", "niconico"

    ICON = File.join(File.dirname(__FILE__), 'mikutter_nicorepo.png').freeze

    @login_state = false
    @last_mail = nil
    @last_pass = nil

    @reader = NicoRepo::NicoRepoReader.new

    def double_try(slug, message)
        retried = false
        begin
            yield
        rescue => e
            activity slug, "#{message}\n#{e.message}"
            unless retried then
                @login_state = false
                login
                retried = true
                retry
            end
        end 
    end

    def update()
        login()

        if @login_state then
            reports = nil
            double_try :mikutter_niconico, "ニコレポの取得に失敗しました" do
                reports = @reader.get
            end

            unless reports.nil? then
                msgs = []
                reports.each {|r|
                    # 適当にごまかしつつユーザっぽいのものをでっちあげる
                    user = Plugin::Niconico::User.new({
                            report_type: r.report_type,
                            idname: lambda{
                                case r.report_type
                                when NicoRepo::VIDEO_UPLOAD, NicoRepo::IMAGE_UPLOAD, NicoRepo::REGISTER_CHBLOG then
                                    "Upload"
                                when NicoRepo::MYLIST_ADD, NicoRepo::IMAGE_CLIP then
                                    "Mylist"
                                when NicoRepo::ADVERTISE then
                                    "Advertise"
                                when NicoRepo::LIVE_BROADCAST, NicoRepo::CO_LIVE_BROADCAST then
                                    "Live"
                                when NicoRepo::CO_LIVE_RESERVE then
                                    "Reserve"
                                else
                                    "Info"
                                end
                            }.call,
                            name: r.author_name,
                            profile_image_url: r.author_image_url,
                            url: r.author_url
                        })
                    message_text = r.content_body
                    unless r.target_title.nil? then 
                        # targetが無いときもあるのでここで面倒を見ておく
                        message_text += "\n\n#{r.target_title}\n#{r.target_short_url}"
                    end
                    # Messageを捏造
                    message = Plugin::Niconico::Nicorepo.new({
                            message: message_text,
                            user: user,
                            created: r.time,
                            url: r.target_url
                        })
                    # タイムラインにどーん
                    msgs << message
                }
                Plugin.call(:extract_receive_message, :niconico_nicorepo, msgs)
            end
        end

        Reserver.new(UserConfig[:mikutter_nicorepo_reload_min] * 60) {
            update()
        }
    end

    def login()
        if (!@login_state || @last_mail != UserConfig[:mikutter_nicorepo_account_mail] || @last_pass != UserConfig[:mikutter_nicorepo_account_pass]) && 
                (UserConfig[:mikutter_nicorepo_account_mail] != "" && UserConfig[:mikutter_nicorepo_account_pass] != "") then
            begin
                @reader.login(UserConfig[:mikutter_nicorepo_account_mail],UserConfig[:mikutter_nicorepo_account_pass])
            rescue
                @login_state = false
                activity :mikutter_niconico, "niconicoログインに失敗しました"
            else
                @last_mail = UserConfig[:mikutter_nicorepo_account_mail]
                @last_pass = UserConfig[:mikutter_nicorepo_account_pass]
                @login_state = true
                activity :mikutter_niconico, "niconicoログインに成功しました"
            end
        end
    end

    filter_extract_datasources do |datasources|
        datasources[:niconico_nicorepo] = "ニコレポ"
        [datasources]
    end

    settings("niconico") do
        settings("niconicoアカウント") do
            input "メールアドレス", :mikutter_nicorepo_account_mail
            inputpass "パスワード", :mikutter_nicorepo_account_pass
        end
        settings("ニコレポリーダー") do
            adjustment("更新間隔(分)", :mikutter_nicorepo_reload_min, 1, 30)
        end
    end

    defimageopener("NicoSeiga", /^http:\/\/(seiga\.nicovideo\.jp\/seiga|nico\.ms)\/im\d+/) do |display_url|
        connection = HTTPClient.new
        page = connection.get_content(display_url)
        next nil if page.empty?
        doc = Nokogiri::HTML(page)
        result = doc.xpath("//meta[@property='og:image']/@content").first
        open(result)
    end

    SerialThread.new {
        update()
    }
end
