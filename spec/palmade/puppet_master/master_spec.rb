require 'spec_helper'

module Palmade::PuppetMaster
  describe Master do
    let(:master) { Master.new }

    describe "#start" do
      subject { master.start }
      context "no family specified" do
        it "should raise an error" do
          expect { master.start }.
            to raise_error /Please specify the family of puppets/
        end
      end

      context "a family was specified" do
        let!(:family) { master.single_family! }

        context "no main puppet specified" do
          it "should raise an error" do
            expect { master.start }.
              to raise_error /Must specify a main puppet to run/
          end
        end

        context "a main puppet was specified" do
          before { family.puppet }

          it "should start without any problems" do
            subject
          end

          it { should be_a Master }
        end
      end
    end

    describe "#join" do
      before do
        family = master.single_family!
        family.puppet
        master.start
      end

      subject { master.join }

      context "worker process" do
        before { Kernel.stub(:fork).and_return nil }

        it "should unjoin" do
          master.should_receive(:unjoin)
          subject
        end
      end

      context "master process" do
        before do
          Kernel.stub(:fork).and_return $$
          master.stub(:do_some_work)
        end

        it "should not unjoin" do
          master.should_not_receive(:unjoin)
          subject
        end
      end
    end

    describe "#unjoin" do
      let(:handler) { double('Worker') }

      context "handler that has #work" do
        before do
          handler.stub(:work)
        end

        it "should call #work on the handler" do
          handler.should_receive(:work)
          master.unjoin(handler)
        end
      end

      context "handler that has #call" do
        before do
          handler.stub(:call)
        end

        it "should call #call on the handler" do
          handler.should_receive(:call)
          master.unjoin(handler)
        end
      end

      context "handler that have both #work and #call" do
        before do
          handler.stub(:work)
          handler.stub(:call)
        end

        it "should call #work on the handler" do
          handler.should_receive(:work)
          master.unjoin(handler)
        end
      end
    end
  end
end
