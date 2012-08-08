require 'open3'
require 'fileutils'
require 'rubygems'
require 'rspec'
require 'vcr'
require 'webmock/rspec'

require 'phrase'
require 'phrase/tool'

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
end

ENV["PHRASE_API_HOST"] ||= "localhost"
ENV["PHRASE_API_PORT"] ||= "3000"
ENV["PHRASE_API_USE_SSL"] ||= "0"

class IO
  def read_available_bytes(chunk_size = 16384, select_timeout = 0.02)
    buffer = []

    return "" if closed? || eof?
    # IO.select cannot be used here due to the fact that it
    # just does not work on windows
    while true
      begin
        IO.select([self], nil, nil, select_timeout)
        break if eof? # stop raising :-(
        buffer << self.readpartial(chunk_size)
      rescue(EOFError)
        break
      end
    end

    return buffer.join
  end
end

module RSpec
  module Helpers
    def reset!
      @in_p, @out_p, @err_p = nil, nil, nil
      Dir["#{tmp}/{gems/*,*}"].each do |dir|
        next if %(base remote1 gems rubygems).include?(File.basename(dir))
        unless ENV['BUNDLER_SUDO_TESTS']
          FileUtils.rm_rf(dir)
        else
          `sudo rm -rf #{dir}`
        end
      end
      FileUtils.mkdir_p(tmp)
      FileUtils.mkdir_p(home)
      Gem.sources = ["file://#{gem_repo1}/"]
      # Gem.configuration.write
    end

    attr_reader :out, :err, :exitstatus

    def in_app_root(&blk)
      Dir.chdir(bundled_app, &blk)
    end

    def in_app_root2(&blk)
      Dir.chdir(bundled_app2, &blk)
    end

    def run(cmd, *args)
      opts = args.last.is_a?(Hash) ? args.pop : {}
      expect_err = opts.delete(:expect_err)
      env = opts.delete(:env)
      groups = args.map {|a| a.inspect }.join(", ")
      setup = "require 'rubygems' ; require 'bundler' ; Bundler.setup(#{groups})\n"
      @out = ruby(setup + cmd, :expect_err => expect_err, :env => env)
    end

    def lib
      File.expand_path('../../../phrase/lib', __FILE__)
    end

    def bundle(cmd, options = {})
      expect_err  = options.delete(:expect_err)
      exitstatus = options.delete(:exitstatus)
      options["no-color"] = true unless options.key?("no-color") || cmd.to_s[0..3] == "exec"

      env = (options.delete(:env) || {}).map{|k,v| "#{k}='#{v}' "}.join
      args = options.map do |k,v|
        v == true ? " --#{k}" : " --#{k} #{v}" if v
      end.join
      gemfile = File.expand_path('../../../bin/bundle', __FILE__)
      cmd = "#{env}#{Gem.ruby} -I#{lib} #{gemfile} #{cmd}#{args}"

      if exitstatus
        sys_status(cmd)
      else
        sys_exec(cmd, expect_err){|i| yield i if block_given? }
      end
    end

    def phrase_cmd(cmd, options = {})
      expect_err  = options.delete(:expect_err)
      exitstatus = options.delete(:exitstatus)

      env = (options.delete(:env) || {}).map{|k,v| "#{k}='#{v}' "}.join
      args = options.map do |k,v|
        v == true ? " --#{k}" : " --#{k} #{v}" if v
      end.join
      gemfile = File.expand_path('../../../phrase/bin/phrase', __FILE__)
      cmd = "#{env}#{Gem.ruby} -I#{lib} #{gemfile} #{cmd}#{args}"

      if exitstatus
        sys_status(cmd)
      else
        sys_exec(cmd, expect_err){|i| yield i if block_given? }
      end
    end

    def phrase(cmd)
      original_stdout = $stdout
      original_stdderr = $stderr
      $stdout = fake_stdout = StringIO.new
      $stderr = fake_stderr = StringIO.new
      begin
        Phrase::Tool.new(cmd.split).run
      ensure
        $stdout = original_stdout
        $stderr = original_stdderr
        @out = fake_stdout.string
        @err = fake_stderr.string
      end
    end

    def ruby(ruby, options = {})
      expect_err = options.delete(:expect_err)
      env = (options.delete(:env) || {}).map{|k,v| "#{k}='#{v}' "}.join
      ruby.gsub!(/["`\$]/) {|m| "\\#{m}" }
      sys_exec(%{#{env}#{Gem.ruby} -I#{lib} -e "#{ruby}"}, expect_err)
    end

    def gembin(cmd)
      lib = File.expand_path("../../../lib", __FILE__)
      old, ENV['RUBYOPT'] = ENV['RUBYOPT'], "#{ENV['RUBYOPT']} -I#{lib}"
      cmd = bundled_app("bin/#{cmd}") unless cmd.to_s.include?("/")
      sys_exec(cmd.to_s)
    ensure
      ENV['RUBYOPT'] = old
    end

    def sys_exec(cmd, expect_err = false)
      Open3.popen3(cmd.to_s) do |stdin, stdout, stderr|
        @in_p, @out_p, @err_p = stdin, stdout, stderr

        yield @in_p if block_given?
        @in_p.close

        @out = @out_p.read_available_bytes.strip
        @err = @err_p.read_available_bytes.strip
      end

      puts @err unless expect_err || @err.empty? || !$show_err
      @out
    end

    def sys_status(cmd)
      @err = nil
      @out = %x{#{cmd}}.strip
      @exitstatus = $?.exitstatus
    end

    def config(config = nil)
      path = bundled_app('.bundle/config')
      return YAML.load_file(path) unless config
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'w') do |f|
        f.puts config.to_yaml
      end
      config
    end

    def gemfile(*args)
      path = bundled_app("Gemfile")
      path = args.shift if Pathname === args.first
      str  = args.shift || ""
      path.dirname.mkpath
      File.open(path.to_s, 'w') do |f|
        f.puts str
      end
    end

    def lockfile(*args)
      path = bundled_app("Gemfile.lock")
      path = args.shift if Pathname === args.first
      str  = args.shift || ""

      # Trim the leading spaces
      spaces = str[/\A\s+/, 0] || ""
      str.gsub!(/^#{spaces}/, '')

      File.open(path.to_s, 'w') do |f|
        f.puts str
      end
    end

    def install_gemfile(*args)
      gemfile(*args)
      opts = args.last.is_a?(Hash) ? args.last : {}
      bundle :install, opts
    end

    def install_gems(*gems)
      gems.each do |g|
        path = "#{gem_repo1}/gems/#{g}.gem"

        raise "OMG `#{path}` does not exist!" unless File.exist?(path)

        gem_command :install, "--no-rdoc --no-ri --ignore-dependencies #{path}"
      end
    end

    alias install_gem install_gems

    def with_gem_path_as(path)
      gem_home, gem_path = ENV['GEM_HOME'], ENV['GEM_PATH']
      ENV['GEM_HOME'], ENV['GEM_PATH'] = path.to_s, path.to_s
      yield
    ensure
      ENV['GEM_HOME'], ENV['GEM_PATH'] = gem_home, gem_path
    end

    def break_git!
      FileUtils.mkdir_p(tmp("broken_path"))
      File.open(tmp("broken_path/git"), "w", 0755) do |f|
        f.puts "#!/usr/bin/env ruby\nSTDERR.puts 'This is not the git you are looking for'\nexit 1"
      end

      ENV["PATH"] = "#{tmp("broken_path")}:#{ENV["PATH"]}"
    end

    def fake_groff!
      FileUtils.mkdir_p(tmp("fake_groff"))
      File.open(tmp("fake_groff/groff"), "w", 0755) do |f|
        f.puts "#!/usr/bin/env ruby\nputs ARGV.inspect\n"
      end

      ENV["PATH"] = "#{tmp("fake_groff")}:#{ENV["PATH"]}"
    end

    def kill_path!
      ENV["PATH"] = ""
    end

    def system_gems(*gems)
      gems = gems.flatten

      FileUtils.rm_rf(system_gem_path)
      FileUtils.mkdir_p(system_gem_path)

      Gem.clear_paths

      gem_home, gem_path, path = ENV['GEM_HOME'], ENV['GEM_PATH'], ENV['PATH']
      ENV['GEM_HOME'], ENV['GEM_PATH'] = system_gem_path.to_s, system_gem_path.to_s

      install_gems(*gems)
      if block_given?
        begin
          yield
        ensure
          ENV['GEM_HOME'], ENV['GEM_PATH'] = gem_home, gem_path
          ENV['PATH'] = path
        end
      end
    end

    def cache_gems(*gems)
      gems = gems.flatten

      FileUtils.rm_rf("#{bundled_app}/vendor/cache")
      FileUtils.mkdir_p("#{bundled_app}/vendor/cache")

      gems.each do |g|
        path = "#{gem_repo1}/gems/#{g}.gem"
        raise "OMG `#{path}` does not exist!" unless File.exist?(path)
        FileUtils.cp(path, "#{bundled_app}/vendor/cache")
      end
    end

    def simulate_new_machine
      system_gems []
      FileUtils.rm_rf default_bundle_path
      FileUtils.rm_rf bundled_app('.bundle')
    end

    def simulate_platform(platform)
      old, ENV['BUNDLER_SPEC_PLATFORM'] = ENV['BUNDLER_SPEC_PLATFORM'], platform.to_s
      yield if block_given?
    ensure
      ENV['BUNDLER_SPEC_PLATFORM'] = old if block_given?
    end

    def simulate_bundler_version(version)
      old, ENV['BUNDLER_SPEC_VERSION'] = ENV['BUNDLER_SPEC_VERSION'], version.to_s
      yield if block_given?
    ensure
      ENV['BUNDLER_SPEC_VERSION'] = old if block_given?
    end

    def revision_for(path)
      Dir.chdir(path) { `git rev-parse HEAD`.strip }
    end
  end
end