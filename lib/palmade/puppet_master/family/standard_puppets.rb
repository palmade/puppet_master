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

        def workling_puppet(k = nil, options = nil, &block)
          create_puppet(:workling, k, options, &block)
        end

        def thin_puppet(k = nil, options = nil, &block)
          create_puppet(:thin, k, options, &block)
        end

        def proxy_puppet(k = nil, options = nil, &block)
          create_puppet(:proxy, k, options, &block)
        end

        def asinc_puppet(k = nil, options = nil, &block)
          create_puppet(:asinc, k, options, &block)
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
          when :asinc
            @puppets[k] = Palmade::PuppetMaster::AsincPuppet.new(options, &block)
          when :eventd
            @puppets[k] = Palmade::PuppetMaster::EventdPuppet.new(options, &block)
          when :loop
            @puppets[k] = Palmade::PuppetMaster::Puppet.new(options, &block)
          when :workling
            @puppets[k] = Palmade::PuppetMaster::WorklingPuppet.new(options, &block)
          when :thin
            @puppets[k] = Palmade::PuppetMaster::ThinPuppet.new(options, &block)
          when :proxy
            @puppets[k] = Palmade::PuppetMaster::ProxyPuppet.new(options, &block)
          else
            raise "Unknown puppet type: #{type}"
          end
        end
      end
    end
  end
end
