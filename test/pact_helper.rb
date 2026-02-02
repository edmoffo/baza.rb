# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'pact/consumer'
require 'pact/consumer/configuration'
require 'webmock'

WebMock.allow_net_connect!
ENV['PACT_DO_NOT_TRACK'] = 'true'

Warning[:deprecated] = false

PROJECT_ROOT = File.expand_path('..', __dir__)
PACT_LOG_DIR = File.expand_path('log', PROJECT_ROOT)

FileUtils.mkdir_p(PACT_LOG_DIR)

Pact.configure do |config|
  config.pact_dir = PROJECT_ROOT
  config.log_dir = PACT_LOG_DIR
end

Pact.service_consumer 'BazaRb' do
  has_pact_with 'Zerocracy' do
    mock_service :zerocracy_api do
      pact_specification_version '2.0.0'
    end
  end
end
