require 'statsd'

module VCAP::CloudController::Metrics
  class StatsdUpdater
    def initialize(statsd=Statsd.new)
      @statsd = statsd
    end

    def update_deploying_count(deploying_count)
      @statsd.gauge('cc.deployments.deploying', deploying_count)
    end

    def update_user_count(user_count)
      @statsd.gauge('cc.total_users', user_count)
    end

    def update_job_queue_length(pending_job_count_by_queue, total)
      @statsd.batch do |batch|
        pending_job_count_by_queue.each do |key, value|
          batch.gauge("cc.job_queue_length.#{key}", value)
        end
        batch.gauge('cc.job_queue_length.total', total)
      end
    end

    def update_thread_info(thread_info)
      @statsd.batch do |batch|
        batch.gauge('cc.thread_info.thread_count', thread_info[:thread_count])
        batch.gauge('cc.thread_info.event_machine.connection_count', thread_info[:event_machine][:connection_count])
        batch.gauge('cc.thread_info.event_machine.threadqueue.size', thread_info[:event_machine][:threadqueue][:size])
        batch.gauge('cc.thread_info.event_machine.threadqueue.num_waiting', thread_info[:event_machine][:threadqueue][:num_waiting])
        batch.gauge('cc.thread_info.event_machine.resultqueue.size', thread_info[:event_machine][:resultqueue][:size])
        batch.gauge('cc.thread_info.event_machine.resultqueue.num_waiting', thread_info[:event_machine][:resultqueue][:num_waiting])
      end
    end

    def update_failed_job_count(failed_jobs_by_queue, total)
      @statsd.batch do |batch|
        failed_jobs_by_queue.each do |key, value|
          batch.gauge("cc.failed_job_count.#{key}", value)
        end
        batch.gauge('cc.failed_job_count.total', total)
      end
    end

    def update_vitals(vitals)
      @statsd.batch do |batch|
        vitals.each do |key, val|
          batch.gauge("cc.vitals.#{key}", val)
        end
      end
    end

    def update_log_counts(counts)
      @statsd.batch do |batch|
        counts.each do |key, val|
          batch.gauge("cc.log_count.#{key}", val)
        end
      end
    end

    def update_task_stats(total_running_tasks, total_memory_in_mb)
      @statsd.batch do |batch|
        batch.gauge('cc.tasks_running.count', total_running_tasks)
        batch.gauge('cc.tasks_running.memory_in_mb', total_memory_in_mb)
      end
    end

    def update_synced_invalid_lrps(lrp_count)
      @statsd.gauge('cc.diego_sync.invalid_desired_lrps', lrp_count)
    end

    def start_staging_request_received
      @statsd.increment('cc.staging.requested')
    end

    def report_staging_success_metrics(duration_ns)
      @statsd.increment('cc.staging.succeeded')
      @statsd.timing('cc.staging.succeeded_duration', nanoseconds_to_milliseconds(duration_ns))
    end

    def report_staging_failure_metrics(duration_ns)
      @statsd.increment('cc.staging.failed')
      @statsd.timing('cc.staging.failed_duration', nanoseconds_to_milliseconds(duration_ns))
    end

    private

    def nanoseconds_to_milliseconds(time_ns)
      (time_ns / 1e6).to_i
    end
  end
end
