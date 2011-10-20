module Palmade
  module PuppetMaster
    class Family
      module StandardPuppets
        def puppet(k = nil, options = nil, &block)
          create_puppet(:loop, k, options, &block)
        end

        def eventd_puppet(k = nil, options = nil, &block)
          create_puppet(:eventd, k, options, &block)
        end

        def thin_puppet(k = nil, options = nil, &block)
          create_puppet(:thin, k, options, &block)
        end

        def mongrel2_puppet(k = nil, options = nil, &block)
          create_puppet(:mongrel2, k, options, &block)
        end

        def create_puppet(type, k = nil, options = nil, &block)
          if options.nil?
            if k.is_a?(Hash)
              options = k
              k = nil
            else
              options = { }
            end
          end

          unless options.include?(:proc_tag)
            options[:proc_tag] = k
          end

          case type
          when :eventd
            @puppets[k] = Palmade::PuppetMaster::EventdPuppet.new(@master, self, options, &block)
          when :loop
            @puppets[k] = Palmade::PuppetMaster::Puppet.new(@master, self, options, &block)
          when :thin
            @puppets[k] = Palmade::PuppetMaster::ThinPuppet.new(@master, self, options, &block)
          when :mongrel2
            @puppets[k] = Palmade::PuppetMaster::Mongrel2Puppet.new(@master, self, options, &block)
          else
            raise "Unknown puppet type: #{type}"
          end
        end
      end
    end
  end
end
