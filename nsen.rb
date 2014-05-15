# -*- coding: utf-8 -*-
require 'net/http'
require 'nokogiri'
require 'open-uri'
require 'rexml/document'
require 'json'
require 'cgi'
require_relative 'nicorepo'

module NicoRepo
    class ThumbInfo
        def initialize(id)
            if id.nil? then
                return
            end

            xml = open("http://ext.nicovideo.jp/api/getthumbinfo/#{id}") {|f|
                f.read
            }
            doc = REXML::Document.new(xml)
            
            @status = doc.elements["nicovideo_thumb_response"].attributes["status"]
            if @status == "ok" then
                e = doc.elements["nicovideo_thumb_response/thumb"]
                @video_id = e.elements["video_id"].text
                @title = e.elements["title"].text
                @movie_type = e.elements["movie_type"].text
                @user_id = e.elements["user_id"]
                @user_id = @user_id.nil? ? nil : @user_id.text.to_i
                unless @user_id.nil? then
                    @user_nickname = e.elements["user_nickname"].text
                end
                @tags = Array.new
                count = 0
                e.elements.each("tags") { |tags_root|
                    if tags_root.attributes["domain"] == "jp" then
                        tags_root.elements.each {|tag|
                            @tags[count] = tag.text
                            count += 1
                        }
                    end
                }
            end
        end

        attr_reader :status, :video_id, :title, :movie_type, :user_id, :user_nickname, :tags
    end

    class NicoRepoReader
        def get_nsen_session(channel)
            page = @agent.get("http://watch.live.nicovideo.jp/api/getplayerstatus/nsen/#{Nsen::CHANNEL[channel]}")
            unless page.at("getplayerstatus").attribute("status").value() == "ok"
                raise "放送は既に終了しています"
            end
            curr = page.at("contents")
            current = nil
            begin
                current = { 
                    video: curr.inner_text().split(":")[1], 
                    title: curr.attribute("title").value() 
                }
            end
            {
                channel: channel,
                current: current,
                stream: Nsen::NsenStream.new(page.at("addr").inner_text, page.at("port").inner_text(), page.at("thread").inner_text())
            }
        end

        def getflv(id)
            @agent.get("http://www.nicovideo.jp/watch/#{id}")
            response = @agent.get("http://flapi.nicovideo.jp/api/getflv/#{id}?as3=1")
            map = {}
            response.body.scan(/([^&]+)=([^&]*)/).each { |i|
                map[i[0]] = i[1]
            }
            return map
        end

        def download(id)
            puts "[nsen.rb] start download #{id}"
            thumbinfo = ThumbInfo.new(id)
            flvinfo = getflv(id)
            filename = File.join(Environment::TMPDIR, "#{id}.#{thumbinfo.movie_type}")
            unless loading?(id) || File.exist?(filename) then
                tmpname = File.join(Environment::TMPDIR, "#{id}.download")
                open(tmpname, "wb") do |f|
                    video_url = CGI::unescape(flvinfo["url"])
                    f.print @agent.get_file(video_url)
                end
                puts "[nsen.rb] downloaded #{id}"
                FileUtils.mv(tmpname, filename)
            else
                puts "[nsen.rb] already downloaded #{id}"
            end
            filename
        end

        def loading?(id)
            File.exist?(File.join(Environment::TMPDIR, "#{id}.download"))
        end
    end
end

module Nsen
    CHANNEL = ["vocaloid", "toho", "nicoindies", "sing", "play", "pv", "hotaru", "allgenre"]
    COMMENT = "comment"
    PLAY = "play"
    PREPARE = "prepare"
    PANEL = "nspanel"
    RESPONSE = "response"

    class NsenStream
        def initialize(address, port, thread)
            @address = address
            @port = port
            @thread = thread
        end

        def start
            Thread.new do
                puts "[nsen.rb] CServer: #{@address}:#{@port}/#{@thread}"
                TCPSocket.open(@address, @port.to_i) do |sock|
                    ticket = "<thread thread=\"#{@thread}\" version=\"20061206\" res_from=\"0\"/>\0"
                    sock.write(ticket)
                    while true
                        stream = sock.gets("\0")
                        e = Nokogiri::XML(stream).elements
                        res = nil
                        begin
                            res = {
                                type: "comment",
                                date: e.attribute("date").value(),
                                text: e.inner_text()
                            }
                            if res[:text].start_with?("/") then
                                sp = res[:text].split(" ")
                                sp[0].slice!(0)
                                res[:type] = sp[0]
                                if res[:text].start_with?("/play") then
                                    res[:video] = sp[1].split(":")[1]
                                    res[:title] = res[:text].match(/main \"(.+)\"/)[1]
                                elsif res[:text].start_with?("/prepare") then
                                    res[:video] = sp[1]
                                end
                            end
                        rescue
                            res = {
                                type: "response",
                                element: e
                            }
                        end
                        yield(res)
                    end
                end
            end
        end
    end
    
    class QueuePlayer
        def initialize(reader, callback)
            @reader = reader
            @callback = callback
            @queue = Queue.new
            @thread = gen_thread
        end

        def gen_thread
            Thread.start do
                while stream = @queue.pop
                    sleep(1) while @reader.loading?(stream[:video])
                    stream.update({ filename: @reader.download(stream[:video]) })
                    if stream[:playback].nil? then
                        play(stream)
                    else
                        stream[:playback].call(stream)
                    end
                end
            end
        end

        def play(stream)
            pid = nil
            out = File.join(File.dirname(stream[:filename]), "nsen.wav")
            begin              
                FileUtils.rm(out) if File.exist?(out)
                if system("ffmpeg -i \"#{stream[:filename]}\" -y -vn -ab 96k -ar 44100 -acodec pcm_s16le #{out}") then
                    @now_playing = stream
                    @callback.call("♪♪ #{stream[:title]}\n http://nico.ms/#{stream[:video]}")
                    pid = IO.popen("aplay -q #{out}").pid
                    Process.wait(pid)
                    pid = nil
                else
                    @callback.call("再生失敗… #{stream[:title]}\n http://nico.ms/#{stream[:video]}")
                end
            ensure
                Process.kill("KILL", pid) unless pid.nil?
                FileUtils.rm(out) if File.exist?(out)
                @now_playing = nil
            end
        end

        def stop()
            @queue.clear
            @thread.kill
            @thread = nil
        end

        def push(stream, &playback)
            @queue.push stream.merge({ playback: playback })
            @thread = gen_thread if @thread.nil?
            puts "[mikutter_nsen] pushed #{stream[:video]}"
        end
        
        private :play
        attr_reader :now_playing
    end
end
