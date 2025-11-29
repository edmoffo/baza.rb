# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'os'
require 'qbash'
require 'rubygems'
require 'rake'
require 'rake/clean'
require 'shellwords'

def name
  @name ||= File.basename(Dir['*.gemspec'].first, '.*')
end

def version
  Gem::Specification.load(Dir['*.gemspec'].first).version
end

ENV['RACK_ENV'] = 'test'

task default: %i[clean test picks rubocop yard]

require 'rake/testtask'
desc 'Run all unit tests'
Rake::TestTask.new(:test) do |t|
  Rake::Cleaner.cleanup_files(['coverage'])
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/test_*.rb'
  t.warning = true
  t.verbose = false
  t.options = ARGV.join(' ').match(/(?:^| )(-- .*)$/)
end

desc 'Run them via Ruby, one by one'
task :picks do
  next if OS.windows?
  (Dir['test/**/*.rb'] + Dir['lib/**/*.rb']).each do |f|
    qbash(
      "bundle exec ruby #{Shellwords.escape(f)} -- --offline",
      log: $stdout, env: { 'RACK_ENV' => 'picks' }
    )
  end
end

require 'yard'
desc 'Build Yard documentation'
YARD::Rake::YardocTask.new do |t|
  t.files = ['lib/**/*.rb']
  t.options = ['--fail-on-warning']
end

require 'rubocop/rake_task'
desc 'Run RuboCop on all directories'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.fail_on_error = true
end
