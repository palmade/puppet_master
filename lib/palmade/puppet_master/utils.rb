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
  end
end
