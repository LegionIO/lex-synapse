# frozen_string_literal: true

require 'legion/settings/extensions'

module Legion
  module Extensions
    module Synapse
      module Helpers
        module TargetSchema
          def self.resolve(function_id:, db:, **)
            return {} unless %i[functions runners extensions].all? { |table| db.table_exists?(table) }

            target = db[:functions].join(:runners, id: :runner_id)
                                   .join(:extensions, id: Sequel[:runners][:extension_id])
                                   .where(Sequel[:functions][:id] => function_id)
                                   .select(Sequel[:functions][:name].as(:function), Sequel[:functions][:args],
                                           Sequel[:runners][:name].as(:runner), Sequel[:extensions][:name].as(:extension)).first
            return {} unless target

            extension = target[:extension].delete_prefix('lex-')
            tools = Legion::Settings::Extensions.tools.select do |tool|
              tool[:extension].to_s.delete_prefix('lex-') == extension && tool[:runner] == target[:runner] &&
                (tool[:function] == target[:function] || tool[:name] == "legion-#{extension}-#{target[:runner]}-#{target[:function]}")
            end
            schemas = tools.map { |tool| tool[:input_schema] }.reject(&:empty?).uniq
            return schemas.first if schemas.one?
            return {} if schemas.size > 1

            signature_schema(args: target[:args])
          end

          def self.signature_schema(args:, **)
            parameters = args.is_a?(String) ? Legion::JSON.load(args) : args
            return {} unless parameters.is_a?(Array) && parameters.all?(Array)

            keywords = parameters.select { |kind, name| %w[key keyreq].include?(kind.to_s) && name }
            { type: 'object', properties: keywords.to_h { |_, name| [name.to_sym, {}] },
              required: keywords.filter_map { |kind, name| name.to_s if kind.to_s == 'keyreq' } }
          end
        end
      end
    end
  end
end
