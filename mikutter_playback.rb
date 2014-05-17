Plugin.create :mikutter_playback do
    Playback = Struct.new(:slug, :name, :play)
    Request = Struct.new(:filename, :server, :callback)

    queue = Queue.new
    qthread = nil

    defdsl :defplayback do |slug, name, &play|
        filter_playback_servers do |servers| 
            [servers + [Playback.new(slug, name, play)]]
        end
    end

    on_play_media do |filename, callback|
        use_server = UserConfig[:mikutter_playback_server]
        Plugin.filtering(:playback_servers, []).first.each do |value|
            if not(use_server) or use_server == value.slug
                queue.push(Request.new(filename, value, callback))
                if qthread.nil? then
                    qthread = Thread.start do
                        while request = queue.pop
                            p request
                            t = nil
                            begin 
                                t = request.server.play.call(request.filename)
                                request.callback.call unless request.callback.nil?
                                t.join if t.is_a?(Thread)
                            ensure
                                t.kill if not(t.nil?) && t.is_a?(Thread)
                            end
                        end
                    end
                end
                break
            end
        end
    end

    on_stop_media do
        queue.clear
        qthread.kill
        qthread = nil
    end
end

require_relative 'mikutter_playback_gstreamer'
require_relative 'mikutter_playback_alsa'
