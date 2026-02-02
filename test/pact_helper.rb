# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'active_support/all'
require 'pact/v2'
require 'webmock'
require_relative '../lib/baza-rb'

WebMock.allow_net_connect!
ENV['PACT_DO_NOT_TRACK'] = 'true'

Warning[:deprecated] = false

PROJECT_ROOT = File.expand_path('..', __dir__)
PACT_LOG_DIR = File.expand_path('log', PROJECT_ROOT)

# Patch to fix Pact V2 bugs:
# 1. format_value does not serialize matchers properly
# 2. with_request and will_respond_with always use JSON content type
# 3. Plain string bodies fail with each_pair error
module Pact
  module V2
    module Consumer
      # Patch for HttpInteractionBuilder.
      class HttpInteractionBuilder
        private

        def format_value(obj)
          return obj if obj.is_a?(String)
          return JSON.dump(obj.as_basic) if obj.is_a?(Pact::V2::Matchers::Base)
          return JSON.dump({ value: obj }) if obj.is_a?(Array)
          JSON.dump(obj)
        end

        def extract_value(val)
          return val['value'] if val.is_a?(Hash) && val.key?('value')
          val
        end

        def format_form(hash)
          InteractionContents.basic(hash).map do |key, val|
            v = extract_value(val)
            "#{key}=#{v}"
          end.join('&')
        end

        public

        def with_request(method: nil, path: nil, query: {}, headers: {}, body: nil)
          part = PactFfi::FfiInteractionPart['INTERACTION_PART_REQUEST']
          PactFfi.with_request(@pact_interaction, method.to_s, format_value(path))
          if query.is_a?(Array)
            idx = Hash.new(0)
            query.each do |item|
              InteractionContents.basic(item).each_pair do |key, val|
                PactFfi.with_query_parameter_v2(@pact_interaction, key.to_s, idx[key], format_value(val))
                idx[key] += 1
              end
            end
          else
            InteractionContents.basic(query).each_pair do |key, val|
              PactFfi.with_query_parameter_v2(@pact_interaction, key.to_s, 0, format_value(val))
            end
          end
          InteractionContents.basic(headers).each_pair do |key, val|
            PactFfi.with_header_v2(@pact_interaction, part, key.to_s, 0, format_value(val))
          end
          return self unless body
          type = headers['Content-Type'] || headers['content-type'] || 'application/json'
          if type.include?('x-www-form-urlencoded')
            PactFfi.with_body(@pact_interaction, part, type, format_form(body))
          elsif body.is_a?(String)
            PactFfi.with_body(@pact_interaction, part, type, body)
          else
            PactFfi.with_body(@pact_interaction, part, 'application/json', format_value(InteractionContents.basic(body)))
          end
          self
        end

        def will_respond_with(status: nil, headers: {}, body: nil)
          part = PactFfi::FfiInteractionPart['INTERACTION_PART_RESPONSE']
          PactFfi.response_status(@pact_interaction, status)
          InteractionContents.basic(headers).each_pair do |key, val|
            PactFfi.with_header_v2(@pact_interaction, part, key.to_s, 0, format_value(val))
          end
          return self unless body
          type = headers['Content-Type'] || headers['content-type']
          if body.is_a?(String)
            PactFfi.with_body(@pact_interaction, part, type || 'text/plain', body)
          elsif body.is_a?(Pact::V2::Matchers::Base)
            val = body.as_basic['value']
            if type.nil? && (val.is_a?(String) || val.is_a?(Numeric))
              PactFfi.with_body(@pact_interaction, part, 'text/plain', val.to_s)
            elsif type&.start_with?('application/json') || type.nil?
              PactFfi.with_body(@pact_interaction, part, type || 'application/json', format_value(body))
            else
              PactFfi.with_body(@pact_interaction, part, type, val.to_s)
            end
          else
            PactFfi.with_body(@pact_interaction, part, 'application/json', format_value(InteractionContents.basic(body)))
          end
          self
        end
      end
    end
  end
end

FileUtils.mkdir_p(PACT_LOG_DIR)

# Mixin for v2 pact tests with minitest.
module PactV2Minitest
  include Pact::V2::Matchers

  def pact_config
    @pact_config ||= Pact::V2::Consumer::PactConfig.new(
      :http,
      consumer_name: 'BazaRb',
      provider_name: 'Zerocracy',
      opts: {
        pact_dir: PROJECT_ROOT,
        log_level: :error,
        pact_specification: 'V3'
      }
    )
  end

  def interaction(description = nil)
    pact_config.new_interaction(description)
  end

  def execute_pact
    server = Pact::V2::Consumer::MockServer.create_for_http!(
      pact: pact_config.pact_handle,
      host: '127.0.0.1',
      port: 0
    )
    yield(server)
  ensure
    if server&.matched?
      server.write_pacts!(pact_config.pact_dir)
    elsif server
      raise "Pact mismatch: #{server.mismatches}"
    end
    server&.cleanup
    pact_config.reset_pact
  end
end
