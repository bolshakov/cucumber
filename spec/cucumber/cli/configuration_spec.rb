require File.dirname(__FILE__) + '/../../spec_helper'
require 'yaml'

module Cucumber
module Cli
  describe Configuration do

    def given_cucumber_yml_defined_as(hash_or_string)
      File.stub!(:exist?).and_return(true)
      cucumber_yml = hash_or_string.is_a?(Hash) ? hash_or_string.to_yaml : hash_or_string
      IO.stub!(:read).with('cucumber.yml').and_return(cucumber_yml)
    end

    def given_the_following_files(*files)
      File.stub!(:directory?).and_return(true)
      Dir.stub!(:[]).and_return(files)
    end

    before(:each) do
      Kernel.stub!(:exit).and_return(nil)
    end

    it "should require files in support paths first" do
      given_the_following_files("/features/step_definitions/foo.rb","/features/support/bar.rb")

      config = Configuration.new(StringIO.new)
      config.parse!(%w{--require /features})

      config.files_to_require.should == [
        "/features/support/bar.rb",
        "/features/step_definitions/foo.rb"
      ]
    end

    it "should require env.rb files first" do
      given_the_following_files("/features/support/a_file.rb","/features/support/env.rb")

      config = Configuration.new(StringIO.new)
      config.parse!(%w{--require /features})

      config.files_to_require.should == [
        "/features/support/env.rb",
        "/features/support/a_file.rb"
      ]
    end

    it "should not require env.rb files when --dry-run" do
      given_the_following_files("/features/support/a_file.rb","/features/support/env.rb")

      config = Configuration.new(StringIO.new)
      config.parse!(%w{--require /features --dry-run})

      config.files_to_require.should == [
        "/features/support/a_file.rb"
      ]
    end

    describe "--exclude" do

      it "excludes a ruby file from requiring when the name matches exactly" do
        given_the_following_files("/features/support/a_file.rb","/features/support/env.rb")

        config = Configuration.new(StringIO.new)
        config.parse!(%w{--require /features --exclude a_file.rb})

        config.files_to_require.should == [
          "/features/support/env.rb"
        ]
      end

      it "excludes all ruby files that match the provided patterns from requiring" do
        given_the_following_files("/features/support/foof.rb","/features/support/bar.rb",
                                  "/features/support/food.rb","/features/blah.rb",
                                  "/features/support/fooz.rb")

        config = Configuration.new(StringIO.new)
        config.parse!(%w{--require /features --exclude foo[df] --exclude blah})

        config.files_to_require.should == [
          "/features/support/bar.rb",
          "/features/support/fooz.rb"
        ]
      end
    end

    describe '#drb?' do
      it "indicates whether the --drb flag was passed in or not" do
        config = Configuration.new(StringIO.new)

        config.parse!(%w{features})
        config.drb?.should == false


        config.parse!(%w{features --drb})
        config.drb?.should == true
      end
    end

    context '--drb' do
      it "removes the --drb flag from the args" do
        config = Configuration.new(StringIO.new)

        args = %w{features --drb}
        config.parse!(args)
        args.should == %w{features}
      end

      it "keeps all other flags intact" do
        config = Configuration.new(StringIO.new)

        args = %w{features --drb --format profile}
        config.parse!(args)
        args.should == %w{features --format profile}
      end

    end

    context '--drb in a profile' do
      it "removes the --drb flag from the args" do
        given_cucumber_yml_defined_as({'server' => '--drb features'})
        config = Configuration.new(StringIO.new)

        args = %w{--profile server}
        config.parse!(args)
        args.should == %w{features}
      end

      it "keeps all other flags intact from all profiles involved" do
        given_cucumber_yml_defined_as({'server' => '--drb features --profile nested',
                                       'nested' => '--verbose'})

        config = Configuration.new(StringIO.new)

        args = %w{--profile server --format profile}
        config.parse!(args)
        args.should == %w{features --verbose --format profile}
      end

    end

    context '--drb in the default profile and no arguments specified' do
      it "expands the profile's arguments into the args excpet for --drb" do
        given_cucumber_yml_defined_as({'default' => '--drb features --format pretty'})
        config = Configuration.new(StringIO.new)
        args = []
        config.parse!(args)
        args.should == %w{features --format pretty}
      end
    end


    context '--profile' do

      it "expands args from profiles in the cucumber.yml file" do
        given_cucumber_yml_defined_as({'bongo' => '--require from/yml'})

        config = Configuration.new(out = StringIO.new, StringIO.new)
        config.parse!(%w{--format progress --profile bongo})
        config.options[:formats].should == [['progress', out]]
        config.options[:require].should == ['from/yml']
      end

      it "expands args from the default profile when no flags are provided" do
        given_cucumber_yml_defined_as({'default' => '--require from/yml'})

        config = Configuration.new(StringIO.new)
        config.parse!([])
        config.options[:require].should == ['from/yml']
      end

      it "provides a helpful error message when a specified profile does not exists in cucumber.yml" do
        given_cucumber_yml_defined_as({'default' => '--require from/yml', 'html_report' =>  '--format html'})

        config = Configuration.new(StringIO.new, error = StringIO.new)
        expected_message = <<-END_OF_MESSAGE
Could not find profile: 'i_do_not_exist'

Defined profiles in cucumber.yml:
  * default
  * html_report
END_OF_MESSAGE

        lambda{config.parse!(%w{--profile i_do_not_exist})}.should raise_error(expected_message)
      end

      it "allows profiles to be defined in arrays" do
        given_cucumber_yml_defined_as({'foo' => [1,2,3]})

        config = Configuration.new(StringIO.new, error = StringIO.new)
        config.parse!(%w{--profile foo})
        config.paths.should == [1,2,3]
      end

      it "notifies the user that an individual profile is being used" do
        given_cucumber_yml_defined_as({'foo' => [1,2,3]})

        config = Configuration.new(out = StringIO.new, error = StringIO.new)
        config.parse!(%w{--profile foo})
        out.string.should =~ /Using the foo profile...\n/
      end

      it "notifies the user when multiple profiles are being used" do
        given_cucumber_yml_defined_as({'foo' => [1,2,3], 'bar' => ['v'], 'dog' => ['v']})

        config = Configuration.new(out = StringIO.new, error = StringIO.new)
        config.parse!(%w{--profile foo --profile bar})
        out.string.should =~ /Using the foo and bar profiles...\n/

        config = Configuration.new(out = StringIO.new, error = StringIO.new)
        config.parse!(%w{--profile foo --profile bar --profile dog})
        out.string.should =~ /Using the foo, bar and dog profiles...\n/
      end




      it "issues a helpful error message when a specified profile exists but is nil or blank" do
        [nil, '   '].each do |bad_input|
          given_cucumber_yml_defined_as({'foo' => bad_input})

          config = Configuration.new(StringIO.new, error = StringIO.new)
          expected_error = /The 'foo' profile in cucumber.yml was blank.  Please define the command line arguments for the 'foo' profile in cucumber.yml./
          lambda{config.parse!(%w{--profile foo})}.should raise_error(expected_error)
        end
      end

      it "issues a helpful error message when no YAML file exists and a profile is specified" do
        File.should_receive(:exist?).with('cucumber.yml').and_return(false)

        config = Configuration.new(StringIO.new, error = StringIO.new)
        expected_error = /cucumber.yml was not found.  Please refer to cucumber's documentation on defining profiles in cucumber.yml./
        lambda{config.parse!(%w{--profile i_do_not_exist})}.should raise_error(expected_error)
      end

      it "issues a helpful error message when cucumber.yml is blank or malformed" do
          expected_error_message = /cucumber.yml was found, but was blank or malformed. Please refer to cucumber's documentation on correct profile usage./

        ['', 'sfsadfs', "--- \n- an\n- array\n", "---dddfd"].each do |bad_input|
          given_cucumber_yml_defined_as(bad_input)

          config = Configuration.new(StringIO.new, error = StringIO.new)
          lambda{config.parse!([])}.should raise_error(expected_error_message)
        end
      end

      it "issues a helpful error message when cucumber.yml can not be parsed" do
        expected_error_message = /cucumber.yml was found, but could not be parsed. Please refer to cucumber's documentation on correct profile usage./

        given_cucumber_yml_defined_as("input that causes an exception in YAML loading")
        YAML.should_receive(:load).and_raise ArgumentError

        config = Configuration.new(StringIO.new, error = StringIO.new)
        lambda{config.parse!([])}.should raise_error(expected_error_message)
      end
    end

    it "should accept --dry-run option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--dry-run})
      config.options[:dry_run].should be_true
    end

    it "should accept --no-source option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--no-source})

      config.options[:source].should be_false
    end

    it "should accept --no-snippets option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--no-snippets})

      config.options[:snippets].should be_false
    end

    it "should set snippets and source to false with --quiet option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--quiet})

      config.options[:snippets].should be_nil
      config.options[:source].should be_nil
    end

    it "should accept --verbose option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--verbose})

      config.options[:verbose].should be_true
    end

    it "should accept --out option" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--out jalla.txt})
      config.options[:formats].should == [['pretty', 'jalla.txt']]
    end

    it "should accept multiple --out options" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--format progress --out file1 --out file2})
      config.options[:formats].should == [['progress', 'file2']]
    end

    it "should accept multiple --format options and put the STDOUT one first so progress is seen" do
      io = StringIO.new
      config = Configuration.new(io)
      config.parse!(%w{--format pretty --out pretty.txt --format progress})
      config.options[:formats].should == [['progress', io], ['pretty', 'pretty.txt']]
    end

    it "should not accept multiple --format options when both use implicit STDOUT" do
      io = StringIO.new
      config = Configuration.new(io)
      lambda do
        config.parse!(%w{--format pretty --format progress})
      end.should raise_error("All but one formatter must use --out, only one can print to STDOUT")
    end

    it "should associate --out to previous --format" do
      config = Configuration.new(StringIO.new)
      config.parse!(%w{--format progress --out file1 --format profile --out file2})
      config.options[:formats].should == [["progress", "file1"], ["profile" ,"file2"]]
    end

    it "should accept --color option" do
      Term::ANSIColor.should_receive(:coloring=).with(true)
      config = Configuration.new(StringIO.new)
      config.parse!(['--color'])
    end

    it "should accept --no-color option" do
      Term::ANSIColor.should_receive(:coloring=).with(false)
      config = Configuration.new(StringIO.new)
      config.parse!(['--no-color'])
    end

    it "should parse tags" do
      config = Configuration.new(StringIO.new)
      includes, excludes = config.parse_tags("one,~two,@three,~@four")
      includes.should == ['one', 'three']
      excludes.should == ['two', 'four']
    end

    describe "--backtrace" do
      before do
        Exception.cucumber_full_backtrace = false
      end

      it "should show full backtrace when --backtrace is present" do
        config = Main.new(['--backtrace'])
        begin
          "x".should == "y"
        rescue => e
          e.backtrace[0].should_not == "#{__FILE__}:#{__LINE__ - 2}"
        end
      end

      after do
        Exception.cucumber_full_backtrace = false
      end
    end

    describe "diff output" do

      it "is enabled by default" do
        config = Configuration.new(StringIO.new)
        config.diff_enabled?.should be_true
      end

      it "is disabled when the --no-diff option is supplied" do
        config = Configuration.new(StringIO.new)
        config.parse!(%w{--no-diff})

        config.diff_enabled?.should be_false
      end

    end

    it "should accept multiple --name options" do
      config = Configuration.new(StringIO.new)
      config.parse!(['--name', "User logs in", '--name', "User signs up"])

      config.options[:name_regexps].should include(/User logs in/)
      config.options[:name_regexps].should include(/User signs up/)
    end

    it "should accept multiple -n options" do
      config = Configuration.new(StringIO.new)
      config.parse!(['-n', "User logs in", '-n', "User signs up"])

      config.options[:name_regexps].should include(/User logs in/)
      config.options[:name_regexps].should include(/User signs up/)
    end

    it "should search for all features in the specified directory" do
      File.stub!(:directory?).and_return(true)
      Dir.should_receive(:[]).with("feature_directory/**/*.feature").
        any_number_of_times.and_return(["cucumber.feature"])

      config = Configuration.new(StringIO.new)
      config.parse!(%w{feature_directory/})

      config.feature_files.should == ["cucumber.feature"]
    end

    it "should allow specifying environment variables on the command line" do
      config = Configuration.new(StringIO.new)
      config.parse!(["foo=bar"])
      ENV["foo"].should == "bar"
      config.feature_files.should == []
    end
    
    it "should allow specifying environment variables in profiles" do
      given_cucumber_yml_defined_as({'selenium' => 'RAILS_ENV=selenium'})
      config = Configuration.new(StringIO.new)
      config.parse!(["--profile", "selenium"])
      ENV["RAILS_ENV"].should == "selenium"
      config.feature_files.should == []
    end

  end
end
end
