# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # ActiveRecord shapes: a model that has no rows, a validation that keeps
      # failing, a column or table the schema does not have.
      #
      # The model, the validation sentence and the missing identifier are the
      # cluster keys. A `RecordNotFound` for `User` and one for `Order` are two
      # different problems and stay apart.
      module Record
        NOT_FOUND  = /Couldn't find (?<model>[A-Z]\w*(?:::\w+)*)/
        VALIDATION = %r{Validation failed: (?<detail>.{1,120}?)(?=\s{2,}|\s+Caused by\b|\s+Failure/Error\b|\z)}
        MISSING    = /(?<what>column|relation|table)\s+["'`]?(?<name>[\w."]+?)["'`]?\s+does not exist/i
        SQLITE     = /no such (?<what>column|table):\s*(?<name>[\w.]+)/i

        module_function

        def call(_failure, text)
          not_found(text) || schema(text) || validation(text)
        end

        def not_found(text)
          match = NOT_FOUND.match(text)
          return nil unless match

          model = match[:model]
          Symptom.new(kind: :record_not_found, key: "record-not-found:#{model}",
                      label: "missing `#{model}` records", detail: "no #{model} found")
        end

        def schema(text)
          match = MISSING.match(text) || SQLITE.match(text)
          return nil unless match

          what = match[:what].downcase
          name = match[:name].delete('"')
          Symptom.new(kind: :schema, key: "schema:#{what}:#{name}",
                      label: "missing database #{what} `#{name}`", detail: "#{what} #{name} does not exist")
        end

        def validation(text)
          match = VALIDATION.match(text)
          return nil unless match

          detail = match[:detail].strip.sub(/[.,]\z/, "")
          return nil if detail.empty?

          Symptom.new(kind: :validation, key: "validation:#{detail.downcase}",
                      label: "validation failure `#{detail}`", detail: detail)
        end
      end
    end
  end
end
