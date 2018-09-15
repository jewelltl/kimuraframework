require 'pmap'

module Kimurai
  class Runner
    attr_reader :jobs, :spiders, :session_info

    def initialize(parallel_jobs:)
      @jobs = parallel_jobs
      @spiders = Kimurai.list
      @start_time = Time.now

      @session_info = {
        id: @start_time.to_i,
        status: :processing,
        start_time: @start_time,
        stop_time: nil,
        environment: Kimurai.env,
        concurrent_jobs: @jobs,
        spiders: @spiders.keys
      }

      if time_zone = Kimurai.configuration.time_zone
        Kimurai.time_zone = time_zone
      end

      ENV.store("SESSION_ID", @start_time.to_i.to_s)
      ENV.store("RBCAT_COLORIZER", "false")
    end

    def run!(exception_on_fail: true)
      running_pids = []

      puts ">>> Runner: started: #{session_info}"
      if at_start_callback = Kimurai.configuration.runner_at_start_callback
        at_start_callback.call(session_info)
      end

      spiders.peach_with_index(jobs) do |spider, i|
        spider_name = spider[0]
        puts "> Runner: started spider: #{spider_name}, index: #{i}"

        pid = spawn("bundle", "exec", "kimurai", "crawl", spider_name, [:out, :err] => "log/#{spider_name}.log")
        running_pids << pid
        Process.wait pid

        running_pids.delete(pid)
        puts "< Runner: stopped spider: #{spider_name}, index: #{i}"
      end
    rescue StandardError, SignalException, SystemExit => e
      session_info.merge!(status: :failed, error: e.inspect, stop_time: Time.now)
      exception_on_fail ? raise(e) : [session_info, e]
    else
      session_info.merge!(status: :completed, stop_time: Time.now)
    ensure
      # Prevent queue to process new intems while executing at_exit body
      Thread.list.each { |t| t.kill if t != Thread.main }
      # Kill currently running spiders
      running_pids.each { |pid| Process.kill("INT", pid) }

      if at_stop_callback = Kimurai.configuration.runner_at_stop_callback
        at_stop_callback.call(session_info)
      end
      puts "<<< Runner: stopped: #{session_info}"
    end
  end
end
