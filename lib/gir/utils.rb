class Utils

  attr_accessor :ui, :gir
  
  def initialize
  end

  def process_configs(config_file)
    config_hash = {}
    configs = File.readlines(config_file)
    for conf in config
      conf_pieces = conf.split('=')
      config_hash[conf_pieces[0].strip] = conf_pieces[1].strip
    end
    return config_hash
  end
  
  def process_schemas(schema_file)
    schemas_hash = {}
    schemas = File.readlines(schema_file)
    for sch in schemas
      schema_pieces = schema.split('=')
      schemas_hash[schema_pieces[0].strip] = schema_pieces[1].split(',').map{ |s| s.strip }
    end
    return schemas_hash
  end

  def write_config(config_hash, config_file)
    file = File.open(config_file, 'w')
    for key,value in config_hash
      file.puts "%s=%s" % [ key, value ]
    end
    file.close
  end
end
