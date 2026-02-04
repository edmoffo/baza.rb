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
      raw = int.dig('response', 'body')
      body = raw.is_a?(Hash) ? raw['content'] : raw
      next if body.nil? || body.empty?
      next if answers.include?(body)
      rules = int.dig('response', 'matchingRules', 'body') || int.dig('response', 'matchingRules')
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

  def test_transfers_payment
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
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
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .given('product exists', { 'pname' => 'pact31' })
      .given('job exists', { 'id' => 555, 'pname' => 'pact31' })
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
        headers: { 'X-Zerocracy-ReceiptId' => match_regex(/^[1-9][0-9]*$/, '8789') }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.transfer('jeff', 42.50, 'for fun', job: 555)
      assert_equal(8789, id)
    end
  end

  def test_pays_fee
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('user is rich')
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .given('product exists', { 'pname' => 'pact96' })
      .given('job exists', { 'id' => 776, 'pname' => 'pact96' })
      .upon_receiving('a fee payment request')
      .with_request(
        method: 'POST',
        path: '/account/fee',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'amount' => match_regex(/^[0-9]+\.[0-9]+$/, '42.770000'),
          'job' => match_regex(/^[0-9]+$/, '776'),
          'summary' => match_regex(/^.+$/, 'the summary'),
          'tab' => match_regex(/^[a-z]+$/, 'unknown')
        }
      )
      .will_respond_with(
        status: 302,
        headers: { 'X-Zerocracy-ReceiptId' => match_regex(/^[1-9][0-9]*$/, '9898') }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      receipt = baza.fee('unknown', 42.77, 'the summary', 776)
      assert_equal(9898, receipt)
    end
  end

  def test_checks_whether_job_is_finished
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact43' })
      .given('job exists', { 'id' => 542, 'pname' => 'pact43' })
      .upon_receiving('a finished check request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/finished/[1-9][0-9]*$}, '/finished/542')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^yes|no$/, 'yes'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.finished?(542))
    end
  end

  def test_reads_verification_verdict
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact98' })
      .given('job exists', { 'id' => 513, 'pname' => 'pact98' })
      .upon_receiving('a verification verdict request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/jobs/[1-9][0-9]*/verified\.txt$}, '/jobs/513/verified.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^(|done|.+)$/, 'done'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.verified(513))
    end
  end

  def test_unlocks_product_by_name
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact25' })
      .given('product is locked', { 'pname' => 'pact25', 'owner' => 'Jeff Lebowski' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('an unlock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/unlock/.+$}, '/unlock/pact25'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'Jeff Lebowski')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.unlock('pact25', 'Jeff Lebowski'))
    end
  end

  def test_locks_product
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact1' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a lock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/lock/[a-z0-9]+$}, '/lock/pact1'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.lock('pact1', 'the-owner')
    end
  end

  # def test_pushes_to_create_job
  #   interaction
  #     .given('user is authenticated')
  #     .given('user is rich')
  #     .given('queue is empty')
  #     .given('product exists', { 'pname' => 'pact72' })
  #     .upon_receiving('a push request')
  #     .with_request(
  #       method: 'PUT',
  #       path: match_regex(%r{/push/[a-z0-9]+}, '/push/pact72'),
  #       body: Factbase.new.export,
  #       headers: { 'Content-Type' => 'application/octet-stream' }
  #     )
  #     .will_respond_with(
  #       status: 200,
  #       body: match_regex(/^[1-9][0-9]*$/, '890'),
  #       headers: { 'Content-Type' => 'text/plain' }
  #     )
  #   execute_pact do |server|
  #     baza = baza_client(server.port)
  #     baza.push('pact72', Factbase.new.export, [])
  #   end
  # end

  def test_finds_recent_job
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact61' })
      .given('job exists', { 'id' => 124, 'pname' => 'pact61' })
      .upon_receiving('a recent job check')
      .with_request(
        method: 'GET',
        path: match_regex(%r{/recent/[a-z0-9]+\.txt}, '/recent/pact61.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[1-9][0-9]*$/, '124'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_equal(124, baza.recent('pact61'))
    end
  end

  def test_checks_product_existence
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact74' })
      .upon_receiving('an exists check')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/exists/[a-z0-9]+$}, '/exists/pact74')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^.+$/, 'yes'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.name_exists?('pact74'))
    end
  end

  def test_checks_job_exit_code
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact22' })
      .given('job exists', { 'id' => 94, 'pname' => 'pact22' })
      .upon_receiving('an exit code request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/exit/[1-9][0-9]*\.txt$}, '/exit/94.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[0-9]+$/, '0'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_predicate(baza.exit_code(94), :zero?)
    end
  end

  def test_reads_stdout
    body = 'hello, друг!'
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('job exists', { 'id' => 17, 'pname' => 'foo' })
      .upon_receiving('a stdout request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/stdout/[1-9][0-9]*\.txt$}, '/stdout/17.txt')
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^.+$/, body),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_equal(body, baza.stdout(17).force_encoding('UTF-8'))
    end
  end

  def test_pulls_factbase_file
    fb = Factbase.new
    fb.insert.then { |f| f.foo = 3.1416 }
    fb.export
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact93' })
      .given('job exists', { 'id' => 47, 'pname' => 'pact93' })
      .upon_receiving('a pull request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/pull/[1-9][0-9]*\.fb$}, '/pull/47.fb')
      )
      .will_respond_with(status: match_status_code('success'))
    execute_pact do |server|
      baza = baza_client(server.port)
      assert(baza.pull(47))
    end
  end

  def test_fails_to_lock
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact2' })
      .given('product is locked', { 'pname' => 'pact2', 'owner' => 'Barack Obama' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a lock request that fails')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/lock/[a-z0-9]+$}, '/lock/pact2'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'Donald Trump')
        }
      )
      .will_respond_with(status: 409)
    execute_pact do |server|
      baza = baza_client(server.port)
      assert_raises(StandardError) { baza.lock('pact2', 'Donald Trump') }
    end
  end

  def test_loads_durable
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact4' })
      .given('durable exists', { 'id' => 427, 'file' => 'bar.txt', 'pname' => 'pact4' })
      .upon_receiving('a durable load request')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/427')
      )
      .will_respond_with(status: match_status_code('success'))
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'loaded.txt')
        baza.durable_load(427, file)
        assert_equal('', File.read(file))
      end
    end
  end

  def test_loads_durable_empty_content
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('durable exists', { 'id' => 54, 'file' => 'bar.txt', 'pname' => 'foo' })
      .given('durable is empty', { 'id' => 54 })
      .upon_receiving('a durable load request for empty content')
      .with_request(
        method: 'GET',
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/54')
      )
      .will_respond_with(
        status: match_status_code('success'),
        body: ''
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'loaded.txt')
        baza.durable_load(54, file)
        assert_equal('', File.read(file))
      end
    end
  end

  def test_locks_durable
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact7' })
      .given('durable exists', { 'id' => 65, 'file' => 'bar.txt', 'pname' => 'pact7' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a durable lock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/durables/[1-9][0-9]*/lock$}, '/durables/65/lock'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'the-owner')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.durable_lock(65, 'the-owner')
    end
  end

  def test_unlocks_durable
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact8' })
      .given('durable exists', { 'id' => 52, 'file' => 'bar.txt', 'pname' => 'pact8' })
      .given('durable is locked', { 'id' => 52, 'owner' => 'Robert DeNiro' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a durable unlock request')
      .with_request(
        method: 'POST',
        path: match_regex(%r{^/durables/[1-9][0-9]*/unlock$}, '/durables/52/unlock'),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'owner' => match_regex(/^.+$/, 'Robert DeNiro')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      baza.durable_unlock(52, 'Robert DeNiro')
    end
  end

  def test_saves_durable
    body = "\x00\x00 hi, dude! \x00\xFF\xFE\x12".b
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact3' })
      .given('durable exists', { 'id' => 426, 'file' => 'bar.txt', 'pname' => 'pact3' })
      .given('durable is locked', { 'id' => 426, 'owner' => 'previous-owner' })
      .upon_receiving('a durable save request')
      .with_request(
        method: 'PUT',
        body:,
        path: match_regex(%r{^/durables/[1-9][0-9]*$}, '/durables/426'),
        headers: {
          'Content-Length' => match_regex(/^[0-9]+$/, body.bytesize.to_s),
          'Content-Type' => 'application/octet-stream'
        }
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^.+$/, 'thanks!'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'tmp.txt')
        File.binwrite(file, body)
        baza.durable_save(426, file)
      end
    end
  end

  def test_enters_when_cached
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'foo' })
      .given('job exists', { 'id' => 188, 'pname' => 'foo' })
      .given('valve exists', { 'badge' => 'bar', 'job' => 188, 'pname' => 'foo', 'result' => 'before' })
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
      result = baza.enter('foo', 'bar', 'no reason', 188) { 'after' }
      assert_equal('before', result)
    end
  end

  def test_enters_when_not_cached
    csrf = match_regex(/^.+$/, 'swordfish')
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact9' })
      .given('valve missing', { 'badge' => 'bar', 'pname' => 'pact9' })
      .upon_receiving('an enter request without cached result')
      .with_request(
        method: 'GET',
        path: '/result',
        query: { 'badge' => match_regex(/^[a-z0-9.]+$/, 'bar') }
      )
      .will_respond_with(
        status: 204,
        body: ''
      )
    interaction
      .upon_receiving('a request for CSRF token')
      .with_request(method: 'GET', path: '/csrf')
      .will_respond_with(
        status: 200,
        body: csrf,
        headers: { 'Content-Type' => 'text/plain' }
      )
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact9' })
      .given('job exists', { 'id' => 183, 'pname' => 'pact9' })
      .given('CSRF token exists', { 'token' => 'swordfish' })
      .upon_receiving('a valve creation request')
      .with_request(
        method: 'POST',
        path: '/valves',
        query: { 'job' => match_regex(/^[0-9]+$/, '183') },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => csrf,
          'badge' => match_regex(/^[a-z0-9.-]+$/, 'bar'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'pact9'),
          'result' => match_regex(/^.+$/, 'after'),
          'why' => match_regex(/^.+$/, 'no reason')
        }
      )
      .will_respond_with(status: 302)
    execute_pact do |server|
      baza = baza_client(server.port)
      result = baza.enter('pact9', 'bar', 'no reason', 183) { 'after' }
      assert_equal('after', result)
    end
  end

  def test_finds_durable
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact10' })
      .given('durable exists', { 'id' => 32, 'file' => 'bar.txt', 'pname' => 'pact10' })
      .upon_receiving('a durable find request')
      .with_request(
        method: 'GET',
        path: '/durable-find',
        query: {
          'file' => match_regex(/[a-z0-9.]+/, 'bar.txt'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'pact10')
        }
      )
      .will_respond_with(
        status: 200,
        body: match_regex(/^[1-9][0-9]*$/, '32'),
        headers: { 'Content-Type' => 'text/plain' }
      )
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.durable_find('pact10', 'bar.txt')
      assert_equal(32, id)
    end
  end

  def test_doesnt_find_durable
    interaction
      .given('user is authenticated')
      .given('product exists', { 'pname' => 'pact11' })
      .given('durable missing', { 'file' => 'bar.txt', 'pname' => 'pact11' })
      .upon_receiving('a durable find request that returns not found')
      .with_request(
        method: 'GET',
        path: '/durable-find',
        query: {
          'file' => match_regex(/[a-z0-9.]+/, 'bar.txt'),
          'pname' => match_regex(/^[a-z0-9]+$/, 'pact11')
        }
      )
      .will_respond_with(status: 404)
    execute_pact do |server|
      baza = baza_client(server.port)
      id = baza.durable_find('pact11', 'bar.txt')
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
