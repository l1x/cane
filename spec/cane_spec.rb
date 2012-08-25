require 'spec_helper'
require "stringio"
require 'cane/cli'

require 'cane/rake_task'

describe 'Cane' do
  def capture_stdout &block
    real_stdout, $stdout = $stdout, StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = real_stdout
  end

  def run(cli_args)
    result = nil
    output = capture_stdout do
      result = Cane::CLI.run(['--no-abc'] + cli_args.split(/\s+/m))
    end

    [output, result ? 0 : 1]
  end

  it 'fails if ABC metric does not meet requirements' do
    file_name = make_file(<<-RUBY)
      class Harness
        def complex_method(a)
          if a < 2
            return "low"
          else
            return "high"
          end
        end
      end
    RUBY

    _, exitstatus = run("--abc-glob #{file_name} --abc-max 1")

    exitstatus.should == 1
  end

  it 'fails if style metrics do not meet requirements' do
    file_name = make_file("whitespace ")

    output, exitstatus = run("--style-glob #{file_name}")
    output.should include("Lines violated style requirements")
    exitstatus.should == 1
  end

  it 'allows upper bound of failed checks' do
    file_name = make_file("whitespace ")

    output, exitstatus = run("--style-glob #{file_name} --max-violations 1")
    exitstatus.should == 0
    output.should include("Lines violated style requirements")
  end

  it 'allows checking of a value in a file' do
    file_name = make_file("89")

    output, exitstatus = run("--gte #{file_name},90")
    output.should include("Quality threshold crossed")
    exitstatus.should == 1
  end

  it 'allows checking of class documentation' do
    file_name = make_file("class NoDoc")

    output, exitstatus = run("--doc-glob #{file_name}")
    exitstatus.should == 1
    output.should include("Classes are not documented")
  end

  context 'with a .cane file' do
    before(:each) do
      file_name = make_file("class NoDoc")
      make_dot_cane("--doc-glob #{file_name}")
    end

    after(:each) do
      unmake_dot_cane
    end

    it 'loads options from a .cane file' do
      output, exitstatus = run('')

      exitstatus.should == 1
      output.should include("Classes are not documented")
    end
  end

  it 'handles invalid unicode input' do
    fn = make_file("\xc3\x28")

    _, exitstatus = run("--style-glob #{fn} --abc-glob #{fn} --doc-glob #{fn}")

    exitstatus.should == 0
  end

  # Push this down into a unit spec
  it 'handles option that does not result in a run' do
    _, exitstatus = run("--help")
    exitstatus.should == 0
  end

  describe 'user-defined checks' do
    let(:class_name) { "C#{rand(10 ** 10)}" }

    it 'allows user-defined checks' do
      fn = make_file(":(")
      check_file = make_file <<-RUBY
        class #{class_name} < Struct.new(:opts)
          def self.options
            {
              unhappy_file: ["File to check", default: [nil]]
            }
          end

          def violations
            [
              description: "Files are unhappy",
              file:        opts.fetch(:unhappy_file),
              label:       ":("
            ]
          end
        end
      RUBY

      out, exitstatus = run(%(
        -r #{check_file}
        --check #{class_name}
        --unhappy-file #{fn}
      ))
      out.should include("Files are unhappy")
      out.should include(fn)
      exitstatus.should == 1
    end

    after do
      if Object.const_defined?(class_name)
        Object.send(:remove_const, class_name)
      end
    end
  end

  it 'works with rake' do
    fn = make_file("90")

    task = Cane::RakeTask.new(:quality) do |cane|
      cane.no_abc = true
      cane.no_doc = true
      cane.no_style = true
      cane.add_threshold fn, :>=, 99
    end

    task.no_abc.should == true

    task.should_receive(:abort)
    out = capture_stdout do
      Rake::Task['quality'].invoke
    end

    out.should include("Quality threshold crossed")
  end

  it 'rake works with user-defined check' do
    my_check = Class.new(Struct.new(:opts)) do
      def violations
        [description: 'test', label: opts.fetch(:some_opt)]
      end
    end

    task = Cane::RakeTask.new(:quality) do |cane|
      cane.no_abc = true
      cane.no_doc = true
      cane.no_style = true
      cane.use my_check, some_opt: "theopt"
    end

    task.should_receive(:abort)
    out = capture_stdout do
      Rake::Task['quality'].invoke
    end

    out.should include("theopt")
  end

  after do
    Rake::Task.clear
  end
end
