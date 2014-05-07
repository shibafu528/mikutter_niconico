# -*- coding: utf-8 -*-
require 'net/http'
require 'nokogiri'
require_relative 'nicorepo'

module NicoRepo
    class NicoRepoReader
        def get_nsen_session(channel)
            p = @agent.get("http://watch.live.nicovideo.jp/api/getplayerstatus/nsen/#{Nsen::CHANNEL[channel]}")
            if not p.at("getplayerstatus").attribute("status").value() == "ok"
                raise "放送は既に終了しています"
            end
            {
                current: p.at("contents").inner_text(),
                stream: Nsen::NsenStream.new(p.at("addr").inner_text, p.at("port").inner_text(), p.at("thread").inner_text())
            }
        end
    end
end

module Nsen
    CHANNEL = ["vocaloid", "toho", "nicoindies", "sing", "play", "pv", "hotaru", "allgenre"]

    class NsenStream
        def initialize(address, port, thread)
            @address = address
            @port = port
            @thread = thread
        end

        def start
            Thread.new do
                started = Time.new.to_i
                yield("started=#{started}")
                TCPSocket.open(@address, @port.to_i) do |sock|
                    ticket = "<thread thread=\"#{@thread}\" version=\"20061206\" res_from=\"-1000\"/>\0"
                    sock.write(ticket)
                    while true
                        stream = sock.gets("\0")
                        e = Nokogiri::XML(stream).elements
                        yield("t:#{e.attribute("date").value()} #{e.inner_text()}")
                    end
                end
            end
        end
    end
end
