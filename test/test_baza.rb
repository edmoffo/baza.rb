# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'factbase'
require 'loog'
require 'securerandom'
require_relative 'test__helper'
require_relative 'pact_helper'
require_relative '../lib/baza-rb'

# Test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2024-2026 Yegor Bugayenko
# License:: MIT
class TestBazaRb < Minitest::Test
  include PactV2Minitest

  Minitest.after_run do
    WebMock.allow_net_connect!
    pact = File.join(__dir__, '..', 'BazaRb-Zerocracy.json')
    raise "Pact file #{pact} not found" unless File.exist?(pact)
    json = JSON.parse(File.read(pact))
    raise 'Pact consumer name missing' unless json.dig('consumer', 'name')
    raise 'Pact provider name missing' unless json.dig('provider', 'name')
    raise 'Pact interactions missing' unless json['interactions'].is_a?(Array)
    raise 'Pact interactions empty' if json['interactions'].empty?
    json['interactions'].each do |int|
      raise "Interaction missing description: #{int}" unless int['description']
      raise "Interaction missing request: #{int['description']}" unless int['request']
      raise "Request missing method: #{int['description']}" unless int.dig('request', 'method')
      raise "Request missing path: #{int['description']}" unless int.dig('request', 'path')
      raise "Interaction missing response: #{int['description']}" unless int['response']
      raise "Response missing status: #{int['description']}" unless int.dig('response', 'status')
    end
    raise 'Pact metadata missing' unless json['metadata']
    raise 'Pact specification version missing' unless json.dig('metadata', 'pactSpecification', 'version')
    answers = %w[yes done]
    json['interactions'].each do |int|
      body = int.dig('response', 'body')
      next if body.nil? || body.empty?
      next if answers.include?(body)
      int.dig('response', 'headers', 'Content-Type')
      rules = int.dig('response', 'matchingRules')
      raise "Response body '#{body}' in '#{int['description']}' looks dynamic but has no matchingRules" if
        rules.nil? && body.match?(/^[0-9]+(\.[0-9]+)?$/)
    end
    json['metadata']['client'] = {
      'name' => 'BazaRb',
      'version' => BazaRb::VERSION,
      'date' => Time.now.utc.iso8601
    }
    File.write(pact, JSON.pretty_generate(json))
  end

  def setup
    WebMock.allow_net_connect!
  end

  def test_version_is_set
    assert(BazaRb::VERSION)
  end

  def test_transfers_payment
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .upon_receiving('a transfer payment request')
      .with_request(
        method: 'POST',
        path: '/account/transfer',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'human' => match_regex(/^[a-z0-9-]+$/, 'jeff'),
          'amount' => match_regex(/^[0-9]+\.[0-9]+$/, '42.500000'),
          'summary' => match_regex(/^.+$/, 'for fun')
        }
      )
      .will_respond_with(
        status: 302,
        headers: { 'X-Zerocracy-ReceiptId' => match_regex(/^[1-9][0-9]*$/, '42') }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.transfer('jeff', 42.50, 'for fun')
      assert_equal(42, id)
    end
  end

  def test_transfers_payment_with_job
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a transfer payment request with job')
      .with_request(
        method: 'POST',
        path: '/account/transfer',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'job' => match_regex(/^[0-9]+$/, '555'),
          'human' => match_regex(/^[a-z0-9-]+$/, 'jeff'),
          'amount' => match_regex(/^[0-9]+\.[0-9]+$/, '42.500000'),
          'summary' => match_regex(/^.+$/, 'for fun')
        }
      )
      .will_respond_with(
        status: 302,
        headers: { 'X-Zerocracy-ReceiptId' => match_regex(/^[1-9][0-9]*$/, '42') }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.transfer('jeff', 42.50, 'for fun', job: 555)
      assert_equal(42, id)
    end
  end

  def test_reads_whoami
    interaction
      .given('user is authenticated')
      .upon_receiving('a whoami request')
      .with_request(method: 'GET', path: '/whoami')
      .will_respond_with(
        status: 200,
        body: match_regex(/^[a-z0-9-]+$/, 'jeff'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_equal('jeff', baza.whoami)
    end
  end

  def test_reads_balance
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .upon_receiving('a balance request')
      .with_request(method: 'GET', path: '/account/balance')
      .will_respond_with(
        status: 200,
        body: match_regex(/^[0-9]+\.[0-9]+$/, '42.33'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_in_delta(42.33, baza.balance)
    end
  end

  def test_checks_whether_job_is_finished
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a finished check request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/finished/[1-9][0-9]*$}, '/finished/42')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^yes|no$/, 'yes'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.finished?(42))
    end
  end

  def test_reads_verification_verdict
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a verification verdict request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/jobs/[1-9][0-9]*/verified\.txt$}, '/jobs/42/verified.txt')
      )
      .will_respond_with(
        status: 200,
        body: 'done',
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.verified(42))
    end
  end

  def test_unlocks_job_by_name
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('an unlock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/unlock/.+$}, '/unlock/foo'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.unlock('foo', 'the-owner'))
    end
  end

  def test_pushes_to_create_job
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .given('product exists', { 'pname' => 'foo' })
      .upon_receiving('a push request')
      .with_request(
        method: 'PUT',
        path: match_regex(%r{/push/[a-z0-9]+}, '/push/foo')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[1-9][0-9]*$/, '42')
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.push('foo', 'hello, world!', [])
    end
  end

  def test_pops_no_jobs
    interaction
      .given('user is authenticated')
      .given('queue is empty')
      .upon_receiving('a pop request with no job')
      .with_request(
        method: 'GET',
        path: '/pop',
        query: { 'owner' => match_regex(/^.+$/, 'me') }
      )
      .will_respond_with(status: 204)
    execute_pact do |server|
      baza = baza_client(server.port)
      Tempfile.open do |zip|
        refute(baza.pop('me', zip.path))
        refute_path_exists(zip.path)
      end
    end
  end

  def test_finishes_jobs
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a finish request')
      .with_request(
        method: 'PUT',
        path: '/finish',
        query: { 'id' => match_regex(/^[1-9][0-9]*$/, '42') }
      )
      .will_respond_with(status: 200)
    execute_pact do |server|
      baza = baza_client(server.port)
      Tempfile.open do |zip|
        File.binwrite(zip.path, 'test data')
        baza.finish(42, zip.path)
      end
    end
  end

  def test_finds_recent_job
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a recent job check')
      .with_request(
        method: 'GET',
        path: match_regex(%r{/recent/[a-z0-9]+\.txt}, '/recent/foo.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[1-9][0-9]*$/, '42'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_equal(42, baza.recent('foo'))
    end
  end

  def test_checks_product_existence
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .upon_receiving('an exists check')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/exists/[a-z0-9]+$}, '/exists/foo')
      )
      .will_respond_with(
        status: 200,
        body: 'yes',
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.name_exists?('foo'))
    end
  end

  def test_checks_job_exit_code
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('an exit code request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/exit/[1-9][0-9]*\.txt$}, '/exit/42.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[0-9]+$/, '0'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_predicate(baza.exit_code(42), :zero?)
    end
  end

  def test_reads_stdout
    body = 'hello, друг!'
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a stdout request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/stdout/[1-9][0-9]*\.txt$}, '/stdout/42.txt')
      )
      .will_respond_with(
        status: 200,
        body: body,
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_equal(body, baza.stdout(42).force_encoding('UTF-8'))
    end
  end

  def test_pulls_factbase_file
    fb = Factbase.new
    fb.insert.then { |f| f.foo = 3.1416 }
    fb.export
    interaction
      .given('user is authenticated')
      .given('job exists', { 'id' => 42 })
      .upon_receiving('a pull request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/pull/[1-9][0-9]*\.fb$}, '/pull/42.fb')
      )
      .will_respond_with(status: 200)
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.pull(42))
    end
  end

  def test_locks_product
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a lock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/lock/[a-z0-9]+$}, '/lock/foo'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.lock('foo', 'the-owner')
    end
  end

  def test_fails_to_lock
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('product is locked', { 'pname' => 'foo' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a lock request that fails')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/lock/[a-z0-9]+$}, '/lock/foo'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 409)
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_raises(StandardError) { baza.lock('foo', 'the-owner') }
    end
  end

  def test_saves_durable
    body = "\x00\x00 hi, dude! \x00\xFF\xFE\x12".b
    interaction
      .given('user is authenticated')
      .given('durable exists', { 'id' => 42 })
      .upon_receiving('a durable save request')
      .with_request(
        method: 'PUT',
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/42')
      )
      .will_respond_with(status: 200, body: '')
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'test.txt')
        File.binwrite(file, body)
        baza.durable_save(42, file)
      end
    end
  end

  def test_loads_durable
    interaction
      .given('user is authenticated')
      .given('durable exists', { 'id' => 42 })
      .upon_receiving('a durable load request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/42')
      )
      .will_respond_with(status: 200, body: 'some data', headers: { 'Content-Type' => 'text/plain' })
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'loaded.txt')
        baza.durable_load(42, file)
        assert_equal('some data', File.read(file))
      end
    end
  end

  def test_loads_durable_empty_content
    interaction
      .given('user is authenticated')
      .given('durable exists', { 'id' => 42 })
      .given('durable is empty', { 'id' => 42 })
      .upon_receiving('a durable load request for empty content')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/42')
      )
      .will_respond_with(status: 206, body: '', headers: { 'Content-Range' => 'bytes 0-0/0' })
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'loaded.txt')
        baza.durable_load(42, file)
        assert_equal('', File.read(file))
      end
    end
  end

  def test_locks_durable
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('durable exists', { 'id' => 42 })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a durable lock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/durables/[1-9][0-9]*/lock$}, '/durables/42/lock'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.durable_lock(42, 'the-owner')
    end
  end

  def test_unlocks_durable
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('durable exists', { 'id' => 42 })
      .given('durable is locked', { 'id' => 42 })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a durable unlock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/durables/[1-9][0-9]*/unlock$}, '/durables/42/unlock'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.durable_unlock(42, 'the-owner')
    end
  end

  def test_pays_fee
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a fee payment request')
      .with_request(
        method: 'POST',
        path: '/account/fee',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'amount' => match_regex(/^[0-9]+\.[0-9]+$/, '42.770000'),
          'job' => match_regex(/^[0-9]+$/, '42'),
          'summary' => match_regex(/^.+$/, 'the summary'),
          'tab' => match_regex(/^[a-z]+$/, 'unknown')
        }
      )
      .will_respond_with(
        status: 302,
        headers: { 'X-Zerocracy-ReceiptId' => match_regex(/^[1-9][0-9]*$/, '42') }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      receipt = baza.fee('unknown', 42.77, 'the summary', 42)
      assert_equal(42, receipt)
    end
  end

  def test_enters_when_cached
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('job exists', { 'job' => 42, 'pname' => 'foo' })
      .given('valve exists', { 'badge' => 'bar', 'job' => 42, 'pname' => 'foo', 'result' => 'before' })
      .upon_receiving('an enter request with cached result')
      .with_request(
        method: 'GET',
        path: '/result',
        query: { 'badge' => match_regex(/^[a-z0-9.]+$/, 'bar') }
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^.+$/, 'before'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      result = baza.enter('foo', 'bar', 'no reason', 42) { 'after' }
      assert_equal('before', result)
    end
  end

  def test_enters_when_not_cached
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('valve missing', { 'badge' => 'bar', 'pname' => 'foo' })
      .upon_receiving('an enter request without cached result')
      .with_request(
        method: 'GET',
        path: '/result',
        query: { 'badge' => match_regex(/^[a-z0-9.]+$/, 'bar') }
      )
      .will_respond_with(
        status: 204,
        body: '',
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(status: 200, body: csrf)
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('job exists', { 'job' => 42, 'pname' => 'foo' })
      .given('valve exists', { 'job' => 42, 'pname' => 'foo', 'badge' => 'bar' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a valve creation request')
      .with_request(
        method: 'POST',
        path: '/valves',
        query: { 'job' => match_regex(/^[0-9]+$/, '42') },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'badge' => match_regex(/^[a-z0-9.-]+$/, 'bar'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'foo'),
          'result' => match_regex(/^.+$/, 'after'),
          'why' => match_regex(/^.+$/, 'no reason')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      result = baza.enter('foo', 'bar', 'no reason', 42) { 'after' }
      assert_equal('after', result)
    end
  end

  def test_finds_durable
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('durable exists', { 'file' => 'bar.txt', 'pname' => 'foo' })
      .upon_receiving('a durable find request')
      .with_request(
        method: 'GET',
        path: '/durable-find',
        query: {
          'file' => match_regex(/[a-z0-9.]+/, 'bar.txt'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'foo')
        }
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[1-9][0-9]*$/, '42'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.durable_find('foo', 'bar.txt')
      assert_equal(42, id)
    end
  end

  def test_doesnt_find_durable
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('durable missing', { 'file' => 'bar.txt', 'pname' => 'foo' })
      .upon_receiving('a durable find request that returns not found')
      .with_request(
        method: 'GET',
        path: '/durable-find',
        query: {
          'file' => match_regex(/[a-z0-9.]+/, 'bar.txt'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'foo')
        }
      )
      .will_respond_with(status: 404)
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.durable_find('foo', 'bar.txt')
      assert_nil(id)
    end
  end

  private

  def baza_client(port, pause: 1)
    BazaRb.new(
      '127.0.0.1',
      port,
      '000',
      ssl: false,
      loog: Loog::NULL,
      compress: false,
      pause:
    )
  end
end
