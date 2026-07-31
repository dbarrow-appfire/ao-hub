# frozen_string_literal: true

require 'logger'
require 'httparty'
require 'active_job'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

module Rails
  def self.logger
    @logger ||= Logger.new(IO::NULL)
  end
end

ActiveJob::Base.queue_adapter = :test

ApplicationJob = ActiveJob::Base

require_relative '../app/services/twenty_client'
require_relative '../app/jobs/twenty_mail_sync_job'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
