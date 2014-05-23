# -*- coding: utf-8 -*-
require 'gst'
require_relative 'gstfix'

Plugin.create :mikutter_playback_gstreamer do
    def create_pipeline(filename)
        audio = Gst::Bin.new("audiobin")
        conv = Gst::ElementFactory.make("audioconvert")
        audiopad = conv.get_static_pad("sink")
        sink = Gst::ElementFactory.make("autoaudiosink")
        audio << conv << sink
        conv >> sink
        audio.add_pad(Gst::GhostPad.new("sink", audiopad))

        pipeline = Gst::Pipeline.new("pipeline")
        src = Gst::ElementFactory.make("filesrc")
        src.location = filename
        decoder = Gst::ElementFactory.make("decodebin")
        decoder.signal_connect("pad-added") do |decoder, pad|
            audiopad = audio.get_static_pad("sink")
            pad.link(audiopad)
        end

        pipeline << src << decoder << audio
        src >> decoder

        pipeline
    end

    defplayback :gstreamer, "GStreamer" do |filename|
        Thread.new do
            pipeline = create_pipeline(filename)
            bus = pipeline.bus
            begin
                pipeline.play
                loop do
                    message = bus.poll(Gst::MessageType::ANY, Gst::CLOCK_TIME_NONE)
                    raise "[Gst] message nil" if message.nil?
                    
                    case message.type
                    when Gst::MessageType::EOS then
                        break
                    when Gst::MessageType::ERROR then
                        activity :error, "[Gst]再生エラー: #{message.parse}"
                        break
                    end
                end
            ensure
                pipeline.stop
            end
        end
    end
end
