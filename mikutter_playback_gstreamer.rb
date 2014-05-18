# -*- coding: utf-8 -*-
require 'gst'

Plugin.create :mikutter_playback_gstreamer do

    defplayback :gstreamer, "GStreamer" do |filename|
        #Thread.new do
            pipeline = Gst::Pipeline.new("pipeline")
            src = Gst::ElementFactory.make("filesrc")
            src.location = filename
            decoder = Gst::ElementFactory.make("decodebin")
            sink = Gst::ElementFactory.make("autoaudiosink")
            pipeline << src << decoder << sink
            src >> decoder >> sink

            loop = GLib::MainLoop.new(nil, false)
            bus = pipeline.bus
            bus.add_watch do |bus, message|
                case message.type
                when Gst::Message::EOS then
                    loop.quit
                when Gst::Message::ERROR then
                    activity :error, "[Gst]再生エラー: #{message.parse}"
                    loop.quit
                end
                true
            end
            
            pipeline.play
            begin
                loop.run
            ensure
                pipeline.stop
            end
        #end
    end
    
end
