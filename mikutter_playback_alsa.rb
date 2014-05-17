# -*- coding: utf-8 -*-
Plugin.create :mikutter_playback_alsa do
    
    defplayback :alsa, "ALSA" do |filename|
        Thread.new do
            pid = nil
            out = File.join(File.dirname(filename), "nsen.wav")
            begin              
                FileUtils.rm(out) if File.exist?(out)
                if system("ffmpeg -i \"#{filename}\" -y -vn -ab 96k -ar 44100 -acodec pcm_s16le #{out}") then
                    pid = IO.popen("aplay -q #{out}").pid
                    Process.wait(pid)
                    pid = nil
                else
                    activity :error, "メディアの再生に失敗しました #{stream[:filename]}"
                end
            ensure
                Process.kill("KILL", pid) unless pid.nil?
                FileUtils.rm(out) if File.exist?(out)
            end
        end
    end
    
end
