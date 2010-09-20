class SysloggerIO
  
  def initialize(syslogger)
    @syslogger = syslogger
  end

  def write(msg)
    @syslogger.add(Logger::INFO, msg) unless msg.nil? || msg.strip == ""
  end
  alias print write
  alias puts write
  alias << write

  # For compatibility with IO
  def binmode; self; end
  def close; nil; end
  def close_read; nil; end
  def close_write; nil; end
  def closed?; true; end
  def closed_read?; true; end
  def closed_write?; true; end

  def fileno; nil; end
  def flush; self; end
  def fsync; 0; end

  def isatty; false; end
  alias tty? isatty

  def sync; true; end
  def sync=(synchronous); true; end
end
