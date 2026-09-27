# frozen_string_literal: true

module RSpec
  module Signal
    module Causal
      # Missing definitions a failure names, read from Ruby exception
      # attributes -- never from message text. See {.call}.
      module Entities
        module_function

        # Missing definitions, read from exception attributes rather than
        # message text:
        #
        #   env:KEY          KeyError whose receiver is ENV itself
        #   const:A::B       NameError for a constant, qualified by its namespace
        #   method:C#m       NoMethodError/NameError on an instance of a class
        #                    defined in this project (never nil, never a core
        #                    class: two nils are not the same nil)
        def call(error, config)
          case error
          when KeyError then env_entity(error)
          when NoMethodError then method_entity(error, config)
          when NameError then constant_entity(error) || method_entity(error, config)
          else []
          end
        rescue StandardError
          []
        end

        def env_entity(error)
          error.receiver.equal?(ENV) ? ["env:#{error.key}"] : []
        rescue ArgumentError
          []
        end

        def constant_entity(error)
          name = error.name.to_s
          return nil unless /\A[A-Z]/.match?(name)

          namespace = error.receiver
          qualified = namespace.is_a?(Module) && namespace != Object && namespace.name
          ["const:#{qualified ? "#{namespace.name}::#{name}" : name}"]
        rescue ArgumentError
          nil
        end

        def method_entity(error, config)
          receiver = error.receiver
          owner = receiver.is_a?(Module) ? receiver : receiver.class
          return [] unless owner.name && first_party_class?(owner, config)

          separator = receiver.is_a?(Module) ? "." : "#"
          ["method:#{owner.name}#{separator}#{error.name}"]
        rescue ArgumentError
          []
        end

        def first_party_class?(owner, config)
          file, = Object.const_source_location(owner.name)
          !file.nil? && config.project.first_party?(file)
        rescue StandardError
          false
        end
      end
    end
  end
end
