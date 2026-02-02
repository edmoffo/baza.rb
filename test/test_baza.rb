# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'securerandom'
require 'pact/consumer'
require 'pact/consumer/spec_hooks'
require_relative 'test__helper'
require_relative 'pact_helper'
require_relative '../lib/baza-rb'

# Test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2024-2026 Yegor Bugayenko
# License:: MIT
class TestBazaRb < Minitest::Test
  include Pact::Consumer::ConsumerContractBuilders

  HOOKS = Pact::Consumer::SpecHooks.new

  # CSRF token matcher - accepts any non-empty string.
  CSRF = Pact.term(generate: 'csrf-token-example', matcher: /^.+$/)

  # Receipt ID matcher - accepts any positive integer.
  RECEIPT = Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)

  # Integer ID matcher - accepts any positive integer.
  ID = Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)

  def self.run_one_method(klass, method, reporter)
    HOOKS.before_all if @pact_started.nil?
    @pact_started = true
    super
  end

  Minitest.after_run do
    WebMock.allow_net_connect!
    HOOKS.after_suite
  end

  def setup
    WebMock.allow_net_connect!
    HOOKS.before_each(name)
  end

  def teardown
    HOOKS.after_each(name)
  end

  def test_version_is_set
    assert(BazaRb::VERSION)
  end

  def test_transfer_payment
    zerocracy_api
      .given('user exists')
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user exists')
      .upon_receiving('a transfer payment request')
      .with(method: :post, path: '/account/transfer')
      .will_respond_with(status: 302, headers: { 'X-Zerocracy-ReceiptId' => RECEIPT })
    id = pact_baza.transfer('jeff', 42.50, 'for fun')
    assert_equal(42, id)
  end

  def test_transfer_payment_with_job
    zerocracy_api
      .given('user exists')
      .upon_receiving('a request for CSRF token for job transfer')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user exists')
      .upon_receiving('a transfer payment request with job')
      .with(method: :post, path: '/account/transfer')
      .will_respond_with(status: 302, headers: { 'X-Zerocracy-ReceiptId' => RECEIPT })
    id = pact_baza.transfer('jeff', 42.50, 'for fun', job: 555)
    assert_equal(42, id)
  end

  def test_reads_whoami
    zerocracy_api
      .given('user exists')
      .upon_receiving('a whoami request')
      .with(method: :get, path: '/whoami')
      .will_respond_with(status: 200, body: Pact.term(generate: 'jeff', matcher: /^[a-z0-9-]+$/))
    assert_equal('jeff', pact_baza.whoami)
  end

  def test_reads_balance
    zerocracy_api
      .given('user exists')
      .upon_receiving('a balance request')
      .with(method: :get, path: '/account/balance')
      .will_respond_with(status: 200, body: '42.33')
    assert_in_delta(42.33, pact_baza.balance)
  end

  def test_checks_whether_job_is_finished
    zerocracy_api
      .given('job exists')
      .upon_receiving('a finished check request')
      .with(method: :get, path: job_path('/finished'))
      .will_respond_with(status: 200, body: 'yes')
    assert(pact_baza.finished?(42))
  end

  def test_reads_verification_verdict
    zerocracy_api
      .given('job exists')
      .upon_receiving('a verification verdict request')
      .with(method: :get, path: job_path('/jobs', '/verified.txt'))
      .will_respond_with(status: 200, body: 'done')
    assert(pact_baza.verified(42))
  end

  def test_unlocks_job_by_name
    zerocracy_api
      .given('job exists')
      .upon_receiving('a request for CSRF token for unlock')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('job exists')
      .upon_receiving('an unlock request')
      .with(method: :post, path: '/unlock/foo')
      .will_respond_with(status: 302)
    assert(pact_baza.unlock('foo', 'x'))
  end

  def test_simple_push
    zerocracy_api
      .given('product exists')
      .upon_receiving('a push request')
      .with(method: :put, path: '/push/simple')
      .will_respond_with(status: 200, body: ID)
    pact_baza.push('simple', 'hello, world!', [])
  end

  def test_simple_pop_with_no_job_found
    zerocracy_api
      .given('queue is empty')
      .upon_receiving('a pop request with no job')
      .with(method: :get, path: '/pop', query: 'owner=me')
      .will_respond_with(status: 204)
    Tempfile.open do |zip|
      refute(pact_baza.pop('me', zip.path))
      refute_path_exists(zip.path)
    end
  end

  def test_simple_finish
    zerocracy_api
      .given('job exists')
      .upon_receiving('a finish request')
      .with(method: :put, path: '/finish', query: job_query('id'))
      .will_respond_with(status: 200)
    Tempfile.open do |zip|
      File.binwrite(zip.path, 'test data')
      pact_baza.finish(42, zip.path)
    end
  end

  def test_simple_recent_check
    zerocracy_api
      .given('job exists')
      .upon_receiving('a recent job check')
      .with(method: :get, path: '/recent/simple.txt')
      .will_respond_with(status: 200, body: ID)
    assert_equal(42, pact_baza.recent('simple'))
  end

  def test_simple_exists_check
    zerocracy_api
      .given('product exists')
      .upon_receiving('an exists check')
      .with(method: :get, path: '/exists/simple')
      .will_respond_with(status: 200, body: 'yes')
    assert(pact_baza.name_exists?('simple'))
  end

  def test_exit_code_check
    zerocracy_api
      .given('job exists')
      .upon_receiving('an exit code request')
      .with(method: :get, path: job_path('/exit', '.txt'))
      .will_respond_with(status: 200, body: '0')
    assert_predicate(pact_baza.exit_code(42), :zero?)
  end

  def test_stdout_read
    zerocracy_api
      .given('job exists')
      .upon_receiving('a stdout request')
      .with(method: :get, path: job_path('/stdout', '.txt'))
      .will_respond_with(status: 200, body: 'hello!')
    refute_empty(pact_baza.stdout(42))
  end

  def test_simple_pull
    zerocracy_api
      .given('job exists')
      .upon_receiving('a pull request')
      .with(method: :get, path: job_path('/pull', '.fb'))
      .will_respond_with(status: 200, body: 'hello, world!')
    assert(pact_baza.pull(42).start_with?('hello'))
  end

  def test_simple_lock_success
    zerocracy_api
      .given('product exists')
      .upon_receiving('a request for CSRF token for lock')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('product exists')
      .upon_receiving('a lock request')
      .with(method: :post, path: '/lock/name')
      .will_respond_with(status: 302)
    pact_baza.lock('name', 'owner')
  end

  def test_simple_lock_failure
    zerocracy_api
      .given('product is locked')
      .upon_receiving('a request for CSRF token for failed lock')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('product is locked')
      .upon_receiving('a lock request that fails')
      .with(method: :post, path: '/lock/name')
      .will_respond_with(status: 409)
    assert_raises(StandardError) { pact_baza.lock('name', 'owner') }
  end

  def test_durable_save
    zerocracy_api
      .given('durable exists')
      .upon_receiving('a durable save request')
      .with(method: :put, path: job_path('/durables'))
      .will_respond_with(status: 200)
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.txt')
      File.write(file, "\x00\x00 hi, dude! \x00\xFF\xFE\x12")
      pact_baza.durable_save(42, file)
    end
  end

  def test_durable_load
    zerocracy_api
      .given('durable exists')
      .upon_receiving('a durable load request')
      .with(method: :get, path: job_path('/durables'))
      .will_respond_with(status: 200, body: 'loaded content')
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'loaded.txt')
      pact_baza.durable_load(42, file)
      assert_equal('loaded content', File.read(file))
    end
  end

  def test_durable_load_empty_content
    zerocracy_api
      .given('durable is empty')
      .upon_receiving('a durable load request for empty content')
      .with(method: :get, path: job_path('/durables'))
      .will_respond_with(status: 206, body: '', headers: { 'Content-Range' => 'bytes 0-0/0' })
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'loaded.txt')
      pact_baza.durable_load(42, file)
      assert_equal('', File.read(file))
    end
  end

  def test_durable_lock
    zerocracy_api
      .given('durable exists')
      .upon_receiving('a request for CSRF token for durable lock')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('durable exists')
      .upon_receiving('a durable lock request')
      .with(method: :post, path: job_path('/durables', '/lock'))
      .will_respond_with(status: 302)
    pact_baza.durable_lock(42, 'test-owner')
  end

  def test_durable_unlock
    zerocracy_api
      .given('durable is locked')
      .upon_receiving('a request for CSRF token for durable unlock')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('durable is locked')
      .upon_receiving('a durable unlock request')
      .with(method: :post, path: job_path('/durables', '/unlock'))
      .will_respond_with(status: 302)
    pact_baza.durable_unlock(42, 'test-owner')
  end

  def test_fee
    zerocracy_api
      .given('user exists')
      .upon_receiving('a request for CSRF token for fee')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user exists')
      .upon_receiving('a fee payment request')
      .with(method: :post, path: '/account/fee')
      .will_respond_with(status: 302, headers: { 'X-Zerocracy-ReceiptId' => RECEIPT })
    receipt = pact_baza.fee('unknown', 10.5, 'Test fee', 123)
    assert_equal(42, receipt)
  end

  def test_enter
    zerocracy_api
      .given('result is cached')
      .upon_receiving('an enter request with cached result')
      .with(method: :get, path: '/result', query: 'badge=test-badge')
      .will_respond_with(status: 200, body: 'cached result')
    result = pact_baza.enter('test-valve', 'test-badge', 'test reason', 123) { 'new result' }
    assert_equal('cached result', result)
  end

  def test_enter_not_cached
    zerocracy_api
      .given('result is not cached')
      .upon_receiving('an enter request without cached result')
      .with(method: :get, path: '/result', query: 'badge=test-badge')
      .will_respond_with(status: 204)
    zerocracy_api
      .given('result is not cached')
      .upon_receiving('a request for CSRF token for valve')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('result is not cached')
      .upon_receiving('a valve creation request')
      .with(method: :post, path: '/valves', query: 'job=123')
      .will_respond_with(status: 302)
    result = pact_baza.enter('test-valve', 'test-badge', 'test reason', 123) { 'new result' }
    assert_equal('new result', result)
  end

  def test_durable_find_found
    zerocracy_api
      .given('durable exists')
      .upon_receiving('a durable find request')
      .with(method: :get, path: '/durable-find', query: 'file=test.txt&pname=test-job')
      .will_respond_with(status: 200, body: ID)
    id = pact_baza.durable_find('test-job', 'test.txt')
    assert_equal(42, id)
  end

  def test_durable_find_not_found
    zerocracy_api
      .given('durable does not exist')
      .upon_receiving('a durable find request that returns not found')
      .with(method: :get, path: '/durable-find', query: 'file=test.txt&pname=test-job')
      .will_respond_with(status: 404)
    id = pact_baza.durable_find('test-job', 'test.txt')
    assert_nil(id)
  end

  def test_get_request_retries_on_429_status_code
    zerocracy_api
      .given('server is busy')
      .upon_receiving('a whoami request that eventually succeeds')
      .with(method: :get, path: '/whoami')
      .will_respond_with(status: 200, body: 'testuser')
    assert_equal('testuser', pact_baza(pause: 0).whoami)
  end

  private

  def pact_baza(pause: 1)
    BazaRb.new(
      'localhost',
      zerocracy_api.mock_service_base_url.split(':').last.to_i,
      '000',
      ssl: false,
      loog: Loog::NULL,
      compress: false,
      pause:
    )
  end

  def job_path(prefix, suffix = '')
    pattern = %r{^#{Regexp.escape(prefix)}/[1-9][0-9]*#{Regexp.escape(suffix)}$}
    Pact.term(generate: "#{prefix}/42#{suffix}", matcher: pattern)
  end

  def job_query(prefix)
    Pact.term(generate: "#{prefix}=42", matcher: /^#{Regexp.escape(prefix)}=[1-9][0-9]*$/)
  end
end
