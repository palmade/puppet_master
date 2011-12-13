module Palmade::PuppetMaster
  module Utils
    # creates and returns a new File object.  The File is unlinked
    # immediately, switched to binary mode, and userspace output
    # buffering is disabled
    def self.tmpio
      fp = begin
             File.open("#{Dir::tmpdir}/#{rand}",
                       File::RDWR|File::CREAT|File::EXCL, 0600)
           rescue Errno::EEXIST
             retry
           end

      File.unlink(fp.path)
      fp.binmode
      fp.sync = true
      fp
    end

    def self.redirect_io(io, path)
      File.open(path, 'ab') { |fp| io.reopen(fp) } if path
      io.sync = true
    end

    def self.symbolize_keys(hash)
      hash.inject({ }) do |options, (key, value)|
        options[key.to_sym] = value
        options
      end
    end

    def self.process_running?(pid)
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
    end

    def self.pidf_running?(pid_file)
      if pid = pidf_read(pid_file)
        process_running?(pid) ? pid : false
      else
        nil
      end
    end

    def self.pidf_read(pid_file)
      if File.exists?(pid_file) && File.file?(pid_file) && pid = File.read(pid_file)
        pid.to_i
      else
        nil
      end
    end

    def self.pidf_kill(pid_file, timeout = 30)
      if timeout == 0
        pidf_send_signal('INT', pid_file)
      else
        pidf_send_signal('QUIT', pid_file)
      end

      Timeout.timeout(timeout) do
        sleep 0.1 while pidf_running?(pid_file)
      end
    rescue Timeout::Error
      pidf_force_kill pid_file
    rescue Interrupt
      pidf_force_kill pid_file
    rescue Errno::ESRCH # No such process
      pidf_force_kill pid_file
    end

    def self.pidf_send_signal(signal, pid_file)
      if pid = pidf_read(pid_file)
        Process.kill(signal, pid)
        pid
      else
        nil
      end
    end

    def self.pidf_force_kill(pid_file)
      if pid = pidf_read(pid_file)
        Process.kill("KILL", pid)
        File.delete(pid_file) if File.exist?(pid_file)
        pid
      else
        nil
      end
    end
  end
end
