# Copyright (c) 2017-2019 Trough Creek Holdings, LLC.  All Rights Reserved

require 'json-schema'

class ConfigSchema
  attr_reader :schema

  def initialize
    @schema = {}
  end

  def validate(config)
    validate_fragment(@schema, config)
  end

  def format_validation_errors(errors, source)
    res = []
    return res if errors.blank?

    if !source.blank? then
      res << "Config validation errors from #{source}:"
    end

    prev_path = []
    errors.each do |path, error|
      fmt_path = ::ConfigSchema.format_path(path, prev_path)
      prev_path = path
      res << fmt_path + ':' + error + "\n"
    end
    return res
  end

  def load_schema(file_name)
    @schema = JSON.parse(File.read(file_name))
  end

  def resolve(ref)
    if ref.length < 2 || ref[0...2] != '#/' then
      raise ArgumentError.new("unsupported schema reference: #{ref.inspect}")
    end

    s = @schema
    path = ref[2..-1].split('/')
    path.each do |elt|
      if s.is_a?(Hash) then
        s = s[elt]
      elsif s.is_a?(Array) then
        s = s[elt.to_i]
      else
        raise ArgumentError.new("invalid fragment type in #{path.inspect}")
      end
    end

    return s
  end

  def self.define_schema(name)
    file_name = Rails.root.join('config/schemas', name + '.json')
    if !File.exists?(file_name) then
      raise ArgumentError.new("no such schema: #{name.inspect}")
    end

    schema = ConfigSchema.new
    schema.load_schema(file_name)
    return schema
  end

  def walk_schema_with_config(config, path=[])
    s = Hashie::Mash.new(schema.deep_dup)

    tree = Hashie::Mash.new { |h, path| h[path] = Hashie::Mash.new(path: path) }

    walk_config(tree, config, path)
    walk_schema(tree, config, s, path)

    result = tree.values.sort { |a, b| a.path <=> b.path }
    return result
  end

  # Produce a path key that shows only changes from previous one
  def self.format_path(path, prev_path)
    res = ''
    matches = true
    path.zip(prev_path).each do |e, pe|
      matches &&= (e == pe)
      if matches then
        res += " " * (e.length + 1)
      else
        res += DbConfig::PATH_DELIM + e
      end
    end
    # get rid of spurious leading '.'
    return res[1..-1]
  end

  protected

  def walk_config(tree, config, path)
    if config.is_a?(Hash) then
      config.each_pair do |k, v|
          walk_config(tree, v, path+[k])
      end
    elsif config.is_a?(Array) then
      config.each_with_index do |v, i|
        walk_config(tree, v, path+[i])
      end
    else
      e = tree[path]
      e.value = config
      e.ruby_type = config.class.to_s
    end
  end

  def walk_schema(tree, config, schema, path)
    e = tree[path]
    if ref = schema.try(:send, '$ref') then
      schema = Hashie::Mash.new(resolve(ref))
    end

    schema_type = schema.try(:fetch, 'type', 'composite')

    # Decorate actual document in tree with schema details
    if !path.empty? then
      e.schema = schema
      e.schema_type = schema_type
      if schema && schema.sensitive then
        e.value = '********'
      end
    end

    return if schema.nil?

    case schema_type
    when 'object'
      properties = schema.fetch('properties', {})
      properties.keys.each do |k|
        walk_schema(tree, config.try(:send, k), schema.properties.send(k), path + [k])
      end

      additional_properties = schema.additionalProperties
      if config.is_a?(Hash) && additional_properties.is_a?(Hash)  then
        additional_keys = config.keys - properties.keys
        additional_keys.each do |k|
          walk_schema(tree, config.send(k), additional_properties, path + [k])
        end
     end

    when 'array'
      items = []
      if schema.items.is_a?(Hash) then
        items = [schema.items]
      else
        items = schema.items
      end

      i = 0
      while tree.member?(path+[i]) do
        item = items[i] || items[0]
        walk_schema(tree, config.try(:[], i), item, path + [i])

        i += 1
      end

      # Any remaining, unused items
      while i < items.length do
        walk_schema(tree, config.try(:[], i), items[i], path + [i])
        i += 1
      end

    when 'composite'
      # BOTCH: fix me
      if schema.not then
        raise ArgumentError.new("not implemented")
      elsif schema.allOf || schema.anyOf || schema.oneOf then
        # re-visiting nodes in tree is ok as we are just decorating
        # order may be significant, but don't guarantee it for now
        [schema.allOf, schema.anyOf, schema.oneOf].compact.each do |s|
          s.each do |sub_schema|
            errors = validate_fragment(sub_schema, config)
            if errors.blank? then
              walk_schema(tree, config, sub_schema, path)
            end
          end
        end
      else
        raise ArgumentError.new("unhandled composite schema: #{schema.as_json} at #{path.as_json}")
      end

    when 'string', 'integer', 'number', 'boolean', 'null'
      # nothing further

    else
      raise ArgumentError.new("unknown schema type: #{schema_type.inspect}")
    end
  end

  def validate_fragment(schema, config)
    r = JSON::Schema::Reader.new(:accept_uri => false, :accept_file => false)
    options = { :schema_reader => r,
                :parse_data => false,
                :errors_as_objects => true }
    err_list = JSON::Validator.fully_validate(schema, config.as_json, options)

    # BOTCH: errors won't match our path specs, but at least we have an
    # intelligble error and a path spec that is simple and machine readable
    errors = []
    err_list.each do |error|
      # Invert JSON::Schema::Attribute.build_fragment
      fragment = error.fetch(:fragment, '')
      path = fragment[2..-1].split('/').join('.')
      errors << [path, error[:message]]
    end

    return errors
  end
end
