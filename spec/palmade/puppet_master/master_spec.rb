require 'spec_helper'

module Palmade::PuppetMaster
  shared_examples "a callback powered object" do
    let(:object_with_callbacks) { described_class.new }

    context "adding a callback to a hook" do
      before do
        object_with_callbacks.on_callback(:on_hook) do
          @count = 1
        end
      end

      context "hook is fired" do
        it "should run the callback for the hook" do
          object_with_callbacks.run_callback(:on_hook)
          @count.should eql 1
        end
      end

      context "when a limit is specified using on_callback_once" do
        before do
          @count = 0

          object_with_callbacks.on_callback_once(:on_callback_limit) do
            @count += 1
          end
        end

        it "should run the callback for the hook once" do
          object_with_callbacks.run_callback(:on_callback_limit)
          object_with_callbacks.run_callback(:on_callback_limit)

          @count.should eql 1
        end
      end

      context "when a limit is specified using run_callback_once" do
        before do
          @count = 0

          object_with_callbacks.on_callback(:on_run_callback_once) do
            @count += 1
          end
        end

        it "should run the callback for the hook once" do
          object_with_callbacks.run_callback_once(:on_run_callback_once)
          object_with_callbacks.run_callback_once(:on_run_callback_once)

          @count.should eql 1
        end
      end

      context "when a limit is specified using run_callback_limit" do
        before do
          @count = 0

          object_with_callbacks.on_callback(:on_run_callback_once) do
            @count += 1
          end
        end

        it "should run the callback for the hook within the specified limit" do
          object_with_callbacks.run_callback_with_limit(:on_run_callback_once, 2)
          object_with_callbacks.run_callback_with_limit(:on_run_callback_once, 2)

          @count.should eql 2
        end

        context "when limit is `nil`" do
          it "should run the callback for the hook with no limits" do
            object_with_callbacks.run_callback_with_limit(:on_run_callback_once, nil)
            object_with_callbacks.run_callback_with_limit(:on_run_callback_once, nil)

            @count.should eql 2
          end
        end

        context "when limit is 0" do
          it "should run the callback for the hook with no limits" do
            object_with_callbacks.run_callback_with_limit(:on_run_callback_once, 0)
            object_with_callbacks.run_callback_with_limit(:on_run_callback_once, 0)

            @count.should eql 2
          end
        end
      end
    end
  end

  describe Master do
    let(:master) { Master.new }

    it_behaves_like "a callback powered object"
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
