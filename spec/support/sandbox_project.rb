# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "json"

# A throwaway project on disk that we run a real `rspec` process against.
#
# Shelling out is deliberate: it exercises the parts a mocked run cannot --
# formatter registration, the default-formatter restoration, artifact writing,
# and the exit status the developer actually sees.
class SandboxProject
  LIB = File.expand_path("../../lib", __dir__)
  EXECUTABLE = File.expand_path("../../exe/rspec-signal", __dir__)
  PARALLEL_EXECUTABLE = File.expand_path("../../exe/rspec-signal-parallel", __dir__)

  attr_reader :root

  def initialize
    @root = Dir.mktmpdir("rspec-signal-sandbox")
  end

  def write(relative_path, contents)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  # The spec_helper a real user would write.
  def install_spec_helper(body = "")
    write("spec/spec_helper.rb", <<~RUBY)
      $LOAD_PATH.unshift(#{LIB.inspect})
      $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
      require "rspec/signal"

      RSpec::Signal.configure do |config|
        config.project_root = #{root.inspect}
      end

      #{body}
    RUBY
  end

  def run(*args)
    command = [RbConfig.ruby, Gem.bin_path("rspec-core", "rspec"),
               "--require", "./spec/spec_helper.rb", "--no-color", *args]
    stdout, stderr, status = Open3.capture3({ "RSPEC_SIGNAL_DISABLE" => nil }, *command, chdir: root)
    Run.new(stdout: stdout, stderr: stderr, status: status.exitstatus, project: self)
  end

  def run_signal(*args)
    env = { "RUBYLIB" => [LIB, ENV.fetch("RUBYLIB", nil)].compact.join(File::PATH_SEPARATOR) }
    stdout, stderr, status = Open3.capture3(
      env, RbConfig.ruby, EXECUTABLE, "--require", "./spec/spec_helper.rb", "--no-color", *args, chdir: root
    )
    Run.new(stdout: stdout, stderr: stderr, status: status.exitstatus, project: self)
  end

  def run_signal_parallel(*args, env: {})
    process_env = { "RUBYLIB" => [LIB, ENV.fetch("RUBYLIB", nil)].compact.join(File::PATH_SEPARATOR) }.merge(env)
    stdout, stderr, status = Open3.capture3(process_env, RbConfig.ruby, PARALLEL_EXECUTABLE, *args, chdir: root)
    Run.new(stdout: stdout, stderr: stderr, status: status.exitstatus, project: self)
  end

  def artifact(name) = File.join(root, "tmp/rspec-signal", name)
  def artifact?(name) = File.file?(artifact(name))
  def read(name) = File.read(artifact(name))
  def json = JSON.parse(read("signal.json"))
  def recorded_examples = File.readlines(File.join(root, "executed.txt"), chomp: true)
  def clear_recorded_examples = FileUtils.rm_f(File.join(root, "executed.txt"))

  def cleanup = FileUtils.rm_rf(root)

  Run = Struct.new(:stdout, :stderr, :status, :project, keyword_init: true) do
    def summary = project.read("signal.md")
    def output = "#{stdout}\n#{stderr}"
  end
end
