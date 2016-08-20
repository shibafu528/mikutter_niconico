# -*- coding: utf-8 -*-
require_relative 'nicorepo'
require_relative 'nsen'
require_relative 'retriever/user'
require_relative 'retriever/nicorepo'

class DownQueue
    def initialize(reader, &callback)
        @reader = reader
        @queue = Queue.new
        @thread = Thread.start do
            while stream = @queue.pop
                sleep(1) while @reader.loading?(stream[:video])
                filename = @reader.download(stream[:video])
                stream.update(filename: filename)
                @now_playing = stream
                callback.call
                Plugin.call(:gst_enq, filename, :mikutter_nsen)
            end
        end
    end

    def enqueue(stream)
        @queue.push(stream)
    end

    def clear
        @queue.clear
    end

    attr_reader :now_playing
end

Plugin.create(:mikutter_niconico) do
    UserConfig[:mikutter_nicorepo_reload_min]   ||= 5
    UserConfig[:mikutter_nicorepo_account_mail] ||= ""
    UserConfig[:mikutter_nicorepo_account_pass] ||= ""
    UserConfig[:mikutter_nsen_default]          ||= 0
    UserConfig[:mikutter_nsen_volume]           ||= 0.8

    defactivity "mikutter_niconico", "niconico"
    defactivity "mikutter_nsen", "Nsen"

    ICON = File.join(File.dirname(__FILE__), 'mikutter_nicorepo.png').freeze

    @login_state = false
    @last_mail = nil
    @last_pass = nil

    @reader = NicoRepo::NicoRepoReader.new
    @infostock = {}
    @nplaying = nil
    @nqueue = DownQueue.new(@reader) do
        np = @nqueue.now_playing
        @infostock[np[:filename]] = np
    end

    on_gst_stderr do |tag, message|
        if connected_nsen? and tag == "mikutter_nsen" and /^Playing (.+)/ =~ message then
            @nplaying = @infostock.delete($1)
            activity :mikutter_nsen, "♪♪ #{@nplaying[:title]}\n http://nico.ms/#{@nplaying[:video]}" unless @nplaying.nil?
        end
    end

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
                    # 本文を生成してEntityも捏造
                    message_text = r.content_body
                    entities = {
                        urls: [{
                                url: r.author_name,
                                expanded_url: r.author_url, 
                                display_url: r.author_name,
                                indices: [0, message_text.length]
                            }],
                        symbols: [],
                        hashtags: [],
                        user_mentions: []
                    }
                    unless r.target_title.nil? then 
                        # targetが無いときもあるのでここで面倒を見ておく
                        message_text += "\n\n#{r.target_title}\n"
                        indices_s = message_text.length
                        message_text += r.target_short_url
                        indices_e = message_text.length
                        entities[:urls] << {
                                    url: r.target_short_url,
                                    expanded_url: r.target_url,
                                    display_url: r.target_short_url,
                                    indices: [indices_s, indices_e]
                                }
                    end
                    # Messageを捏造
                    message = Plugin::Niconico::Nicorepo.new({
                            message: message_text,
                            user: user,
                            created: r.time,
                            url: r.target_url,
                            entities: entities
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

    def connected_nsen?() 
        @nstream != nil
    end

    def connect_nsen(channel)
        login()
        session = nil
        double_try :mikutter_nsen, "Nsenの接続に失敗しました" do
            session = @reader.get_nsen_session(channel)
        end
        Plugin.call(:gst_set_volume, UserConfig[:mikutter_nsen_volume], :mikutter_nsen)
        unless session.nil? then 
            # 現在再生中の曲情報が付いていたらそれを再生する
            @nqueue.enqueue(session[:current]) unless session[:current].nil?

            @nstream = session[:stream].start do |stream|
                case stream[:type]
                when Nsen::PLAY then
                    @nqueue.enqueue(stream)
                when Nsen::PREPARE then
                    unless @reader.loading?(stream[:video]) then
                        Thread.new do
                            @reader.download(stream[:video])
                        end
                    end
                when Nsen::RESPONSE then
                    activity :mikutter_nsen, "Nsenに接続しました! (#{Nsen::CHANNEL[session[:channel]]})"
                else
                    info stream
                end
            end
        end
    end

    def disconnect_nsen() 
        @nstream.kill
        @nstream = nil
        @nplaying = nil
        Plugin.call(:gst_stop, :mikutter_nsen)
        activity :mikutter_nsen, "Nsenから切断しました"
    end

    filter_extract_datasources do |datasources|
        datasources[:niconico_nicorepo] = "ニコレポ"
        [datasources]
    end

    command(:mikutter_nsen_play,
        name: "Nsen 接続/切断",
        condition: lambda{ |opt| true},
        visible: false,
        role: :window) do |opt|
        if connected_nsen? then
            disconnect_nsen()
        else
            connect_nsen(UserConfig[:mikutter_nsen_default])
        end
    end

    command(:mikutter_nsen_change,
        name: "Nsen チャンネル切り替え",
        condition: lambda{ |opt| true },
        visible: false,
        role: :window) do |opt|
        
        dialog = Gtk::Dialog.new("Nsen", 
            $main_application_window, 
            Gtk::Dialog::DESTROY_WITH_PARENT,
            [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL])
        
        list = [
            "ch0_1 VOCALOID",
            "ch0_2 東方",
            "ch0_3 ニコニコインディーズ",
            "ch0_4 歌ってみた",
            "ch0_5 演奏してみた",
            "ch0_6 PV",
            "ch9_9 蛍の光",
            "ch0_0 オールジャンル"
        ]

        table = Gtk::Table.new(4, 2, true)
        for i in 0..3 do
            for j in 0..1 do
                ch = i*2+j
                button = Gtk::Button.new(list[ch])
                button.signal_connect("activate", ch) do |instance, ch|
                    disconnect_nsen() if connected_nsen?
                    connect_nsen(ch)
                    dialog.response(Gtk::Dialog::RESPONSE_ACCEPT)
                end
                button.signal_connect("clicked") do |instance|
                    instance.activate
                end
                table.attach_defaults(button, j, j+1, i, i+1)
            end
        end
        table.set_row_spacings(2)
        table.set_column_spacings(4)
        
        dialog.vbox.add(table)
        dialog.show_all()

        result = dialog.run()
        dialog.destroy()
    end

    command(:mikutter_nsen_volume,
        name: "Nsen ボリューム調整GUI",
        condition: lambda{ |opt| true},
        visible: false,
        role: :window) do |opt|
        dialog = Gtk::Dialog.new("Nsen Volume", 
            $main_application_window, 
            Gtk::Dialog::DESTROY_WITH_PARENT,
            [Gtk::Stock::OK, Gtk::Dialog::RESPONSE_OK])
        
        scale = Gtk::HScale.new(0.0, 1.0, 0.01)
        scale.value = UserConfig[:mikutter_nsen_volume].to_f / 100.0
        scale.draw_value = true
        scale.signal_connect("value-changed") do
            volume = (scale.value*100).to_i
            Plugin.call(:gst_set_volume, volume, :mikutter_nsen)
            UserConfig[:mikutter_nsen_volume] = volume
        end
        dialog.vbox.add(scale)
        dialog.show_all()
        
        dialog.run()
        dialog.destroy()
    end

    command(:mikutter_nsen_now,
        name: "Nsen NowPlayingツイート",
        condition: lambda{ |opt| connected_nsen? && @nplaying != nil},
        visible: false,
        role: :window) do |opt|
        text = "#{@nplaying[:title]} http://nico.ms/#{@nplaying[:video]} #NowPlaying"
        Service.primary.update(message: text)
    end

    command(:mikutter_nsen_info,
        name: "Nsen 現在再生中の動画を確認",
        condition: lambda{ |opt| connected_nsen? && @nplaying != nil},
        visible: false,
        role: :window) do |opt|
        text = "Nsen 現在再生中の曲は\n#{@nplaying[:title]}\nhttp://nico.ms/#{@nplaying[:video]}\nですっ！"
        activity :system, text
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
            select("デフォルトの接続先", :mikutter_nsen_default,
                0 => "ch01 VOCALOID",
                1 => "ch02 東方",
                2 => "ch03 ニコニコインディーズ",
                3 => "ch04 歌ってみた",
                4 => "ch05 演奏してみた",
                5 => "ch06 PV",
                6 => "ch99 蛍の光",
                7 => "ch00 オールジャンル"
                )
             boolean("mikutter終了時に動画キャッシュを削除", :mikutter_nsen_autoclean).
                tooltip("Nsen経由でダウンロードした動画を葬ります。\n" + 
                "この機能を使用しない場合は同じ動画を二度も取得せずに済みますが、回線速度やストレージ容量と相談で。")
        end
    end
    
    Plugin[:openimg].addsupport(/^http:\/\/(seiga\.nicovideo\.jp\/seiga|nico\.ms)\/im\d+/, "tag" => "meta", "attribute" => "content", "property" => "og:image")

    SerialThread.new {
        update()
    }

    at_exit {
        disconnect_nsen if connected_nsen?
        FileUtils.rm(Dir.glob(File.expand_path(Environment::TMPDIR) + "/*.download"))
        if UserConfig[:mikutter_nsen_autoclean] then
            FileUtils.rm(Dir.glob(File.expand_path(Environment::TMPDIR) + "/*.mp4"))
            FileUtils.rm(Dir.glob(File.expand_path(Environment::TMPDIR) + "/*.flv"))
        end
    }
end
