# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2024-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'factbase'
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

  def test_transfers_payment
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user is logged in')
      .upon_receiving('a transfer payment request')
      .with(
        method: :post,
        path: '/account/transfer',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'human' => Pact.term(generate: 'jeff', matcher: /^[a-z0-9-]+$/),
          'amount' => Pact.term(generate: '42.50', matcher: /^[0-9]+\.[0-9]+$/),
          'summary' => Pact.term(generate: 'for fun', matcher: /^.+$/)
        }
      )
      .will_respond_with(
        status: 302,
        headers: {
          'X-Zerocracy-ReceiptId' => Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)
        }
      )
    id = pact_baza.transfer('jeff', 42.50, 'for fun')
    assert_equal(42, id)
  end

  def test_transfers_payment_with_job
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user is logged in')
      .upon_receiving('a transfer payment request with job')
      .with(
        method: :post,
        path: '/account/transfer',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'job' => Pact.term(generate: '555', matcher: /^[0-9]+$/),
          'human' => Pact.term(generate: 'jeff', matcher: /^[a-z0-9-]+$/),
          'amount' => Pact.term(generate: '42.50', matcher: /^[0-9]+\.[0-9]+$/),
          'summary' => Pact.term(generate: 'for fun', matcher: /^.+$/)
        }
      )
      .will_respond_with(
        status: 302,
        headers: {
          'X-Zerocracy-ReceiptId' => Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)
        }
      )
    id = pact_baza.transfer('jeff', 42.50, 'for fun', job: 555)
    assert_equal(42, id)
  end

  def test_reads_whoami
    zerocracy_api
      .given('user is logged in')
      .upon_receiving('a whoami request')
      .with(method: :get, path: '/whoami')
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: 'jeff', matcher: /^[a-z0-9-]+$/),
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert_equal('jeff', pact_baza.whoami)
  end

  def test_reads_balance
    zerocracy_api
      .given('user is logged in')
      .upon_receiving('a balance request')
      .with(method: :get, path: '/account/balance')
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: '42.33', matcher: %r{^[0-9]+\.[0-9]+$}),
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert_in_delta(42.33, pact_baza.balance)
  end

  def test_checks_whether_job_is_finished
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('a finished check request')
      .with(
        method: :get,
        path: Pact.term(generate: '/finished/42', matcher: %r{^/finished/[1-9][0-9]*$})
      )
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: 'yes', matcher: /^yes|no$/),
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert(pact_baza.finished?(42))
  end

  def test_reads_verification_verdict
    zerocracy_api
      .given('job 42 exists')
      .upon_receiving('a verification verdict request')
      .with(
        method: :get,
        path: Pact.term(
          generate: '/jobs/42/verified.txt',
          matcher: %r{^/jobs/[1-9][0-9]*/verified\.txt$}
        )
      )
      .will_respond_with(
        status: 200,
        body: 'done',
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert(pact_baza.verified(42))
  end

  def test_unlocks_job_by_name
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('job exists')
      .upon_receiving('an unlock request')
      .with(
        method: :post,
        path: Pact.term(generate: '/unlock/foo', matcher: %r{^/unlock/.+$}),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          _csrf: CSRF,
          owner: Pact.term(generate: 'the-owner', matcher: /^.+$/)
        }
      )
      .will_respond_with(status: 302)
    assert(pact_baza.unlock('foo', 'the-owner'))
  end

  def test_pushes_to_create_job
    zerocracy_api
      .given('product "foo" exists')
      .upon_receiving('a push request')
      .with(
        method: :put,
        path: Pact.term(generate: '/push/foo', matcher: %r{/push/[a-z0-9]+})
      )
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)
      )
    pact_baza.push('foo', 'hello, world!', [])
  end

  def test_pops_no_jobs
    zerocracy_api
      .given('queue is empty')
      .upon_receiving('a pop request with no job')
      .with(
        method: :get,
        path: '/pop',
        query: {
          owner: Pact.term(generate: 'me', matcher: %r{^.+$})
        }
      )
      .will_respond_with(status: 204)
    Tempfile.open do |zip|
      refute(pact_baza.pop('me', zip.path))
      refute_path_exists(zip.path)
    end
  end

  def test_finishes_jobs
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('a finish request')
      .with(
        method: :put,
        path: '/finish',
        query: {
          id: Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)
        }
      )
      .will_respond_with(status: 200)
    Tempfile.open do |zip|
      File.binwrite(zip.path, 'test data')
      pact_baza.finish(42, zip.path)
    end
  end

  def test_finds_recent_job
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('a recent job check')
      .with(
        method: :get,
        path: Pact.term(generate: '/recent/foo.txt', matcher: %r{/recent/[a-z0-9]+\.txt})
      )
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/),
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert_equal(42, pact_baza.recent('foo'))
  end

  def test_checks_product_existence
    zerocracy_api
      .given('product "foo" exists')
      .upon_receiving('an exists check')
      .with(
        method: :get,
        path: Pact.term(generate: '/exists/foo', matcher: %r{^/exists/[a-z0-9]+$})
      )
      .will_respond_with(
        status: 200,
        body: 'yes',
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert(pact_baza.name_exists?('foo'))
  end

  def test_checks_job_exit_code
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('an exit code request')
      .with(
        method: :get,
        path: Pact.term(generate: '/exit/42.txt', matcher: %r{^/exit/[1-9][0-9]*\.txt$})
      )
      .will_respond_with(
        status: 200,
        body: '0',
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert_predicate(pact_baza.exit_code(42), :zero?)
  end

  def test_reads_stdout
    body = 'hello, друг!'
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('a stdout request')
      .with(
        method: :get,
        path: Pact.term(generate: '/stdout/42.txt', matcher: %r{^/stdout/[1-9][0-9]*\.txt$})
      )
      .will_respond_with(
        status: 200,
        body:,
        headers: { 'Content-Type' => 'text/plain' }
      )
    assert_equal(body, pact_baza.stdout(42).force_encoding('UTF-8'))
  end

  def test_pulls_factbase_file
    fb = Factbase.new
    fb.insert.then { |f| f.foo = 42 }
    bin = fb.export
    zerocracy_api
      .given('job #42 exists')
      .upon_receiving('a pull request')
      .with(
        method: :get,
        path: Pact.term(generate: '/pull/42.fb', matcher: %r{^/pull/[1-9][0-9]*\.fb$})
      )
      .will_respond_with(status: 200)
    assert(pact_baza.pull(42))
  end

  def test_locks_product
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('product "foo" exists')
      .upon_receiving('a lock request')
      .with(
        method: :post,
        path: Pact.term(generate: '/lock/foo', matcher: %r{^/lock/[a-z0-9]+$}),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'owner' => Pact.term(generate: 'the-owner', matcher: %r{^.+$})
        }
      )
      .will_respond_with(status: 302)
    pact_baza.lock('foo', 'the-owner')
  end

  def test_fails_to_lock
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('product "foo" is locked')
      .upon_receiving('a lock request that fails')
      .with(
        method: :post,
        path: Pact.term(generate: '/lock/foo', matcher: %r{^/lock/[a-z0-9]+$}),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'owner' => Pact.term(generate: 'the-owner', matcher: %r{^.+$})
        }
      )
      .will_respond_with(status: 409)
    assert_raises(StandardError) { pact_baza.lock('foo', 'the-owner') }
  end

  def test_saves_durable
    body = "\x00\x00 hi, dude! \x00\xFF\xFE\x12".b
    zerocracy_api
      .given('durable #42 exists')
      .upon_receiving('a durable save request')
      .with(
        method: :put,
        path: Pact.term(generate: '/durables/42', matcher: %r{^/durables/[1-9][0-9]*$})
      )
      .will_respond_with(status: 200, body: '')
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.txt')
      File.binwrite(file, body)
      pact_baza.durable_save(42, file)
    end
  end

  def test_loads_durable
    zerocracy_api
      .given('durable #42 exists')
      .upon_receiving('a durable load request')
      .with(method: :get, path: Pact.term(generate: '/durables/42', matcher: %r{^/durables/[1-9][0-9]*$}))
      .will_respond_with(status: 200, body: Pact.term(generate: 'some data', matcher: %r{^.+$}))
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'loaded.txt')
      pact_baza.durable_load(42, file)
      assert_equal('some data', File.read(file))
    end
  end

  def test_loads_durable_empty_content
    zerocracy_api
      .given('durable is empty')
      .upon_receiving('a durable load request for empty content')
      .with(method: :get, path: Pact.term(generate: '/durables/42', matcher: %r{^/durables/[1-9][0-9]*$}))
      .will_respond_with(status: 206, body: '', headers: { 'Content-Range' => 'bytes 0-0/0' })
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'loaded.txt')
      pact_baza.durable_load(42, file)
      assert_equal('', File.read(file))
    end
  end

  def test_locks_durable
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('durable #42 exists')
      .upon_receiving('a durable lock request')
      .with(
        method: :post,
        path: Pact.term(generate: '/durables/42/lock', matcher: %r{^/durables/[1-9][0-9]*/lock$}),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'owner' => Pact.term(generate: 'the-owner', matcher: %r{^.+$})
        }
      )
      .will_respond_with(status: 302)
    pact_baza.durable_lock(42, 'the-owner')
  end

  def test_unlocks_durable
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('durable #42 is locked')
      .upon_receiving('a durable unlock request')
      .with(
        method: :post,
        path: Pact.term(generate: '/durables/42/unlock', matcher: %r{^/durables/[1-9][0-9]*/unlock$}),
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'owner' => Pact.term(generate: 'the-owner', matcher: %r{^.+$})
        }
      )
      .will_respond_with(status: 302)
    pact_baza.durable_unlock(42, 'the-owner')
  end

  def test_pays_fee
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('user is logged in')
      .upon_receiving('a fee payment request')
      .with(
        method: :post,
        path: '/account/fee',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'amount' => Pact.term(generate: '42.77', matcher: %r{^[0-9]+\.[0-9]+$}),
          'job' => Pact.term(generate: '42', matcher: %r{^[0-9]+$}),
          'summary' => Pact.term(generate: 'the summary', matcher: %r{^.+$}),
          'tab' => Pact.term(generate: 'unknown', matcher: %r{^[a-z]+$})
        }
      )
      .will_respond_with(
        status: 302,
        headers: {
          'X-Zerocracy-ReceiptId' => Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/)
        }
      )
    receipt = pact_baza.fee('unknown', 42.77, 'the summary', 42)
    assert_equal(42, receipt)
  end

  def test_enters_when_cached
    zerocracy_api
      .given('result for the "bar" badge for job #42 and "foo" product exists as "before"')
      .upon_receiving('an enter request with cached result')
      .with(
        method: :get,
        path: '/result',
        query: {
          badge: Pact.term(generate: 'bar', matcher: /^[a-z0-9.]+$/)
        }
      )
      .will_respond_with(
        status: 200,
        body: Pact.term(generate: 'before', matcher: /^.+$/),
        headers: { 'Content-Type' => 'text/plain' }
      )
    result = pact_baza.enter('foo', 'bar', 'no reason', 42) { 'after' }
    assert_equal('before', result)
  end

  def test_enters_when_not_cached
    zerocracy_api
      .given('result for the "bar" badge for "foo" product not exists')
      .upon_receiving('an enter request without cached result')
      .with(
        method: :get,
        path: '/result',
        query: {
          badge: Pact.term(generate: 'bar', matcher: /^[a-z0-9.]+$/)
        }
      )
      .will_respond_with(
        status: 204,
        body: '',
        headers: { 'Content-Type' => 'text/plain' }
      )
    zerocracy_api
      .upon_receiving('a request for CSRF token')
      .with(method: :get, path: '/csrf')
      .will_respond_with(status: 200, body: CSRF)
    zerocracy_api
      .given('job #42 exists for the "foo" product and valve "bar" not exists')
      .upon_receiving('a valve creation request')
      .with(
        method: :post,
        path: '/valves',
        query: {
          job: Pact.term(generate: '42', matcher: /^[0-9]+$/)
        },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: {
          '_csrf' => CSRF,
          'badge' => Pact.term(generate: 'bar', matcher: /^[a-z0-9\.-]+$/),
          'pname' => Pact.term(generate: 'foo', matcher: /^[a-z0-9]+$/),
          'result' => Pact.term(generate: 'after', matcher: /^.+$/),
          'why' => Pact.term(generate: 'no reason', matcher: /^.+$/)
        }
      )
      .will_respond_with(status: 302)
    result = pact_baza.enter('foo', 'bar', 'no reason', 42) { 'after' }
    assert_equal('after', result)
  end

  def test_finds_durable
    zerocracy_api
      .given('durable "bar.txt" exists for the "foo" product')
      .upon_receiving('a durable find request')
      .with(
        method: :get,
        path: '/durable-find',
        query: {
          file: Pact.term(generate: 'bar.txt', matcher: /[a-z0-9.]+/),
          pname: Pact.term(generate: 'foo', matcher: /^[a-z0-9]+$/)
        }
      )
      .will_respond_with(status: 200, body: Pact.term(generate: '42', matcher: /^[1-9][0-9]*$/))
    id = pact_baza.durable_find('foo', 'bar.txt')
    assert_equal(42, id)
  end

  def test_doesnt_find_durable
    zerocracy_api
      .given('durable "bar.txt" does not exist for the "foo" product')
      .upon_receiving('a durable find request that returns not found')
      .with(
        method: :get,
        path: '/durable-find',
        query: {
          file: Pact.term(generate: 'bar.txt', matcher: /[a-z0-9.]+/),
          pname: Pact.term(generate: 'foo', matcher: /^[a-z0-9]+$/)
        }
      )
      .will_respond_with(status: 404)
    id = pact_baza.durable_find('foo', 'bar.txt')
    assert_nil(id)
  end

  private

  def pact_baza(pause: 1)
    BazaRb.new(
      'localhost',
      zerocracy_api.mock_service_base_url.split(':').last.to_i,
      '000',
      ssl: false,
      loog: Loog::VERBOSE,
      compress: false,
      pause:
    )
  end
end
