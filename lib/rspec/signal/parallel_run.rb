# frozen_string_literal: true

require "fileutils"
require "json"

module RSpec
  module Signal
    # Filesystem protocol shared by parallel_tests workers and the parent merger.
    module ParallelRun
      RUN_ID = "RSPEC_SIGNAL_RUN_ID"
      REGISTRY = "RSPEC_SIGNAL_RUN_REGISTRY"

      module_function

      def worker?
        !ENV[RUN_ID].to_s.empty? && ENV.key?("TEST_ENV_NUMBER")
      end

      def worker_id
        value = ENV.fetch("TEST_ENV_NUMBER", "").to_s
        value.empty? ? "1" : value
      end

      def write_worker(report, config)
        directory = File.join(config.output_path, "workers", ENV.fetch(RUN_ID), worker_id)
        FileUtils.mkdir_p(directory)
        path = File.join(directory, "signal.json")
        payload = report.worker_h(write_full: config.write_full, config: config)
                        .merge(worker: worker_id, configuration: configuration_h(config))
        atomic_write(path, "#{JSON.pretty_generate(payload)}\n")
        register(path)
      end

      def configuration_h(config)
        %i[output_dir project_root max_frames max_external_context max_project_frames fallback_frames
           max_message_lines max_diff_lines reduce_html max_html_chars max_affected_examples max_groups
           relate_failures max_clusters max_cluster_specs code_path_depth max_code_paths
           write_json write_full write_gitignore track_history terminal_summary capture_capybara
           capture_page_html].to_h { |name| [name, config.public_send(name)] }
      end

      def register(path)
        registry = ENV.fetch(REGISTRY)
        FileUtils.mkdir_p(registry)
        atomic_write(File.join(registry, "#{worker_id}.path"), "#{path}\n")
      end

      def atomic_write(path, contents)
        temporary = "#{path}.#{Process.pid}.tmp"
        File.write(temporary, contents)
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary)
      end
    end
  end
end
