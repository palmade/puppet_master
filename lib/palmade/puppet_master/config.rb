require 'yaml'

module Palmade::PuppetMaster
  class Config < Hash
    def load_from_yaml(yaml_file)
      yamlc = YAML.load_file(yaml_file)
      if yamlc.is_a?(Hash)
        update(Palmade::PuppetMaster::Utils.symbolize_keys(yamlc))
      else
        raise "Yaml content should return a hash object"
      end
    end

    alias :update! :update

    def symbolize_keys
      n = { }
      keys.each { |k| n[k.to_sym] = self[k] }
      n
    end
  end
end
