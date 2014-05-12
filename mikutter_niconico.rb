# -*- coding: utf-8 -*-
require_relative 'nicorepo'
require_relative 'nsen'

Plugin.create(:mikutter_nicorepo) do
    UserConfig[:mikutter_nicorepo_reload_min]   ||= 5
    UserConfig[:mikutter_nicorepo_account_mail] ||= ""
    UserConfig[:mikutter_nicorepo_account_pass] ||= ""

    defactivity "mikutter_niconico", "niconico"
    defactivity "mikutter_nsen", "Nsen"
    defactivity "mikutter_nicorepo", "ニコレポリーダー"

    ICON = File.join(File.dirname(__FILE__), 'mikutter_nicorepo.png').freeze

    @login_state = false
    @last_mail = nil
    @last_pass = nil

    @nplaying = nil
    @nthread = nil

    @reader = NicoRepo::NicoRepoReader.new()

    def update()
        if @login_state == false || @last_mail != UserConfig[:mikutter_nicorepo_account_mail] || @last_pass != UserConfig[:mikutter_nicorepo_account_pass] then
            login()
        end
        
        if @login_state then
            reports = nil
            retried = false # リトライ管理
            begin
                reports = @reader.get()
            rescue => e
                activity :mikutter_nicorepo, "ニコレポの取得に失敗しました\n" + e.message
                # ログインしてからリトライする処理は1回の取得操作で一度きりということにしておく
                # あまり負荷かけたくないし...
                unless retried then
                    login()
                    retried = true
                    retry
                end
            end

            unless reports.nil? then
                reports.each {|r|
                    # 適当にごまかしつつユーザっぽいのものをでっちあげる
                    user = User.new({
                            :id => 1,
                            :idname => lambda{
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
                            :name => r.author_name,
                            :nickname => r.author_name,
                            :profile_image_url => r.author_image_url,
                            :url => r.author_url,
                            :detail => ""
                        })
                    # 本文を生成してEntityも捏造
                    message_text = r.content_body
                    entities = {
                        :urls => [],
                        :symbols => [],
                        :hashtags => [],
                        :user_mentions => []
                    }
                    entities[:urls] << {
                        :url => r.author_name,
                        :expanded_url => r.author_url, 
                        :display_url => r.author_name,
                        :indices => [0, message_text.length]
                    }
                    unless r.target_title.nil? then 
                        # targetが無いときもあるのでここで面倒を見ておく
                        message_text += "\n\n#{r.target_title}\n"
                        indices_s = message_text.length
                        message_text += r.target_short_url
                        indices_e = message_text.length
                        entities[:urls] << {
                                    :url => r.target_short_url,
                                    :expanded_url => r.target_url,
                                    :display_url => r.target_short_url,
                                    :indices => [indices_s, indices_e]
                                }
                    end
                    # Messageを捏造
                    message = Message.new({
                            :id => r.time.to_i,
                            :message => message_text,
                            :user => user,
                            :source => "nicorepo",
                            :created => r.time,
                            :entities => entities
                        })
                    # タイムラインにどーん
                    timeline(:nicorepo) << message
                }
                activity :mikutter_nicorepo, "ニコレポを更新しました"
            end
        end

        Reserver.new(UserConfig[:mikutter_nicorepo_reload_min] * 60) {
            update()
        }
    end

    def login() 
        if UserConfig[:mikutter_nicorepo_account_mail] != "" && UserConfig[:mikutter_nicorepo_account_pass] != "" then
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

    def play(stream)
        activity :mikutter_niconico, "再生準備中 #{stream[:video]} / #{stream[:title]}"
        Thread.new do
            fn = @reader.download(stream[:video])
            out = fn + ".wav"
            if system("ffmpeg -i \"#{fn}\" -y -vn -ab 96k -ar 44100 -acodec pcm_s16le #{out}") then
                @nplaying = stream
                Plugin.call(:play_sound, out)
                activity :mikutter_nsen, "♪♪ #{stream[:video]} / #{stream[:title]}"
            else
                @nplaying = nil
                activity :mikutter_niconico, "再生に失敗しました #{stream[:video]} / #{stream[:title]}"
            end
        end
    end

    def prepare(stream)
        activity :mikutter_niconico, "プリロード(#{stream[:video]})"
        Thread.new do
            fn = @reader.download(stream[:video])
            activity :mikutter_niconico, "プリロード完了(#{fn})"
        end
    end

    tab(:mikutter_nicorepo, "ニコレポリーダー") do
        set_icon(ICON)
        timeline :nicorepo
    end

    command(:mikutter_nsen_play,
        name: "Nsenに接続",
        condition: lambda{ |opt| @nthread == nil},
        visible: false,
        role: :window) do |opt|
        session = @reader.get_nsen_session(0)
        unless session[:current] == nil then
            play(session[:current])
        end
        @nthread = session[:stream].start do |stream|
            case stream[:type]
            when Nsen::N_PLAY then
                play(stream)
            when Nsen::N_PREPARE then
                prepare(stream)
            when Nsen::N_COMMENT then
                activity :mikutter_nsen, "[Nsen] #{stream[:text]}"
            when "response" then
                activity :mikutter_nsen, "Nsenに接続しました! (#{Nsen::CHANNEL[session[:channel]]})"
            else
                p stream
            end
        end
    end

    command(:mikutter_nsen_now,
        name: "Nsen NowPlayingツイート",
        condition: lambda{ |opt| @nplaying != nil},
        visible: false,
        role: :window) do |opt|
        text = "#{@nplaying[:title]} http://nico.ms/#{@nplaying[:video]} #NowPlaying"
        Service.primary.update(message: text)
    end
        

    settings("niconico") do
        settings("niconicoアカウント") do
            input "メールアドレス", :mikutter_nicorepo_account_mail
            inputpass "パスワード", :mikutter_nicorepo_account_pass
        end
        settings("ニコレポリーダー") do
            adjustment("更新間隔(分)", :mikutter_nicorepo_reload_min, 1, 30)
        end
        settings("Nsen") do
        end
    end
    
    Plugin[:openimg].addsupport(/^http:\/\/(seiga\.nicovideo\.jp\/seiga|nico\.ms)\/im\d+/, "tag" => "meta", "attribute" => "content", "property" => "og:image")

    SerialThread.new {
        update()
    }

    at_exit {
        FileUtils.rm(Dir.glob(File.join(Environment::TMPDIR, "*.(mp4|flv)(.wav)?")))
    }
end
