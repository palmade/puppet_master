require 'spec_helper'

module Palmade::PuppetMaster
  describe Configurator do
    let(:file)          { Tempfile.new('configurator.rb') }
    let!(:file_path)     { file.path }
    let(:configurator) { Configurator.new }

    describe "(dynamic accessors)" do
      context "when setting a variable to a value," do
        subject { Configurator.new }
        before  { subject.variable = 'value' }

        it { should_not raise_error NoMethodError }
      end

      context "when getting a value from a variable," do
        let(:value) { 'value' }

        before do
          configurator.variable = value
          configurator.variable
        end

        it { should_not raise_error NoMethodError }

        describe "the returned value" do
          subject { configurator.variable }

          it { should equal value }
        end
      end
    end

    describe "(dynamic creation of sections)" do
      context "calling an undefined section," do
        it "should raise ArgumentError" do
          expect { configurator.undefined_section }.to raise_error ArgumentError
        end
      end

      context "defining a section," do
        it "should not raise ArgumentError" do
          expect {
            configurator.common do |m, config, controller|
              nil
            end
          }.to_not raise_error ArgumentError
        end
      end
    end

    describe "#call_section" do
      context "calling an undefined section," do
        it "should raise ArgumentError" do
          expect {
            configurator.call_section('undefined_section', {})
          }.to raise_error ArgumentError
        end
      end

      context "calling a defined section," do
        it "should call the defined section" do
          configurator.defined_section do |m, config, controller|
            configurator.defined_section
          end

          configurator.should_receive(:defined_section)
          configurator.call_section('defined_section')
        end
      end
    end

    describe "#configure" do
      context "given a path to a file that exists," do
        let(:file_contents) { 'nil' }
        before              { file.syswrite(file_contents) }

        it "should return the same Configurator instance" do
          subject.configure(file_path).should be subject
        end

        it "should evaluate the file's contents using instance_eval" do
          subject.should_receive(:instance_eval).with(file_contents,
                                                      anything)
          subject.configure(file_path)
        end

        it "should display configurator compilation errors within the
            context of the configurator file" do
              subject.should_receive(:instance_eval).with(anything,
                                                          file_path)
              subject.configure(file_path)
            end
      end

      context "file doesn't exist," do
        before { file.close! }

        it "should raise ArugmentError" do
          expect { subject.configure(file_path) }.to raise_error ArgumentError, /not found/
        end
      end
    end

    describe "#include?" do
      subject { configurator.include? 'i_exist' }

      context "section exists" do
        before do
          configurator.i_exist do |m, config, controller|
            nil
          end
        end

        it { should be true }
      end

      context "section doesn't exist" do
        it { should be false }
      end
    end

    describe "class method #configure" do
      let(:args)         { {:hello => 'world'} }
      let!(:configurator) { Configurator.new(args) }

      it "should create a new Configurator instance passing the passed args" do
        Configurator.should_receive(:new).with(args) { configurator }

        Configurator.configure(file_path, args)
      end

      it "should return a Configurator instance" do
        Configurator.configure(file_path, args).should be_a Configurator
      end

      it "should call #configure" do
        Configurator.stub(:new) { configurator }
        configurator.should_receive(:configure) { configurator }

        Configurator.configure(file_path, args)
      end
    end
  end
end
