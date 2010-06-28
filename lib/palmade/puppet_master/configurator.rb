module Palmade::PuppetMaster
  class Configurator
    def self.configure(file_path, *args)
      c = Class.new(self).new(*args)
      c.configure(file_path)
    end

    def initialize(*args)
      @args = args
      @sections = { }
    end

    def append_args(*args)
      unless args.empty?
        @args += @args
      end
    end

    def method_missing(method, *args, &block)
      method = method.to_s
      if method[-1,1] == '='
        # this is a setter
        # create a new accessor

        var_name = method[0..-2]
        eval = <<EVAL
def #{var_name}=(val)
  @#{var_name} = val
end

def #{var_name}
  @#{var_name}
end
EVAL
        self.class.send(:class_eval, eval, __FILE__, __LINE__)
        self.send(method, *args)
      elsif block_given?
        update_section(method, *args, &block)

        # create a new section
        eval = <<EVAL
def #{method}(*args, &block)
  if block_given?
    update_section(#{method}, *args, &block)
  else
    call_section(#{method}, *args)
  end
end
EVAL
        self.class.send(:class_eval, eval, __FILE__, __LINE__)
      else
        # generate an error!
        raise ArgumentError, "Section #{method} not defined."
      end
    end

    def include?(section)
      @sections.include?(prep(section))
    end
    alias :has? :include?

    def configure(file_path)
      if File.exists?(file_path)
        fcontents = File.read(file_path)
        self.instance_eval(fcontents, file_path)
      else
        raise ArgumentError, "File #{file_path} not found"
      end
      self
    end

    def call_section(section, *args)
      section = prep(section)
      if @sections.include?(section)
        @sections[section].each do |block|
          block.call(*(args + @args))
        end
      else
        raise ArgumentError, "Section #{section} not defined."
      end
    end
    alias :call :call_section
    alias :include :call_section

    protected

    def prep(section)
      section.to_sym
    end

    def update_section(section, *args, &block)
      return unless block_given?

      options = args.last.is_a?(Hash) ? args.pop : { }
      command = args.first || :push

      section = prep(section)
      unless @sections.include?(section)
        @sections[section] = [ ]
      end

      case command
      when :unshift
        @sections[section].unshift(block)
      when :push
        @sections[section].push(block)
      else
        raise ArgumentError, "Unknown update command: #{command}"
      end
    end
  end
end
