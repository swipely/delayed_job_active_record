require "helper"
require "delayed/backend/active_record"

describe Delayed::Backend::ActiveRecord::Job do
  it_behaves_like "a delayed_job backend"

  describe '#invoke_job' do
    let(:payload_object) { double(:payload_object) }
    subject { described_class.new }

    before do
      subject.stub(:payload_object).and_return(payload_object)
      payload_object.stub(:perform)
    end

    context "when Rails is not in the environment" do
      it "calls super" do
        defined?(Rails).should_not be, 'Rails has not been required'
        subject.invoke_job
      end
    end

    if defined?(ActiveSupport::TaggedLogging) && defined?(Rails)
      context "when Rails is in the environment" do
        let(:logger) { double(:logger) }
        before { require 'rails' }

        it "logs the entry and exit of the job, tagged with the job's name" do
          Rails.logger = logger
          Rails.logger.should_receive(:tagged).and_yield
          Rails.logger.should_receive(:info).with("Entering job")
          Rails.logger.should_receive(:info).with("Exiting job")
          subject.invoke_job
        end
      end
    end
  end

  describe ".clear_lock!" do
    shared_examples_for "with retry" do
      let(:attempts) { Delayed::Job::RETY_ATTEMPTS}

      context "when an unrecoverable deadlock" do

        it "will try 11 times and then raise the exception" do
          Delayed::Job.should_receive(:by_locked).with('name').exactly(attempts + 1).times.and_raise deadlock_error

          expect do
            Delayed::Job.clear_locks!('name')
          end.to raise_error(Delayed::Backend::ActiveRecord::RetryError)

        end
      end

      context "when a recoverable deadlock" do
        it "will retry 10 times and then pass" do
          Delayed::Job.should_receive(:by_locked).with('name').exactly(attempts).times.and_raise deadlock_error

          Delayed::Job.should_receive(:by_locked).with('name').and_return(
            double(:records, :update_all => true)
          )

          Delayed::Job.clear_locks!('name')
        end
      end
    end

    describe "should handle Deadlock error" do
      let(:deadlock_error) do
        Delayed::Backend::ActiveRecord::RetryError.new("Exception: Mysql2::Error: Deadlock found when trying to get lock; try restarting transaction: <transaction details>")
      end

      it_behaves_like "with retry"
    end

    describe "should handle Lock timeout" do
      let(:deadlock_error) do
        Delayed::Backend::ActiveRecord::RetryError.new("Exception: Mysql2::Error: Lock wait timeout exceeded;")
      end

      it_behaves_like "with retry"
    end
  end

  describe '#save!' do
    it "will retry" do
      subject.class.should_receive(:retry_on_deadlock).with(10)
      subject.save!
    end
  end

  describe "#destroy" do
    it "succeeds even if the payload_object is corrupt" do
      allow(YAML).to receive(:load_dj).and_raise(ArgumentError)
      subject.handler = "handler"
      subject.save!

      expect { subject.destroy }.to_not raise_error
    end
  end

  describe "reserve_with_scope" do
    let(:worker) { double(name: "worker01", read_ahead: 1) }
    let(:scope)  { double(limit: limit, where: double(update_all: nil)) }
    let(:limit)  { double(job: job) }
    let(:job)    { double(id: 1) }

    before do
      allow(Delayed::Backend::ActiveRecord::Job.connection).to receive(:adapter_name).at_least(:once).and_return(dbms)
    end

    context "for a dbms without a specific implementation" do
      let(:dbms) { "OtherDB" }

      it "uses the plain sql version" do
        expect(Delayed::Backend::ActiveRecord::Job).to receive(:reserve_with_scope_using_default_sql).once
        Delayed::Backend::ActiveRecord::Job.reserve_with_scope(scope, worker, Time.now)
      end
    end
  end

  context "db_time_now" do
    after do
      Time.zone = nil
      ActiveRecord::Base.default_timezone = :local
    end

    it "returns time in current time zone if set" do
      Time.zone = "Eastern Time (US & Canada)"
      expect(%(EST EDT)).to include(Delayed::Job.db_time_now.zone)
    end

    it "returns UTC time if that is the AR default" do
      Time.zone = nil
      ActiveRecord::Base.default_timezone = :utc
      expect(Delayed::Backend::ActiveRecord::Job.db_time_now.zone).to eq "UTC"
    end

    it "returns local time if that is the AR default" do
      Time.zone = "Central Time (US & Canada)"
      ActiveRecord::Base.default_timezone = :local
      expect(%w(CST CDT)).to include(Delayed::Backend::ActiveRecord::Job.db_time_now.zone)
    end
  end

  describe "after_fork" do
    it "calls reconnect on the connection" do
      expect(ActiveRecord::Base).to receive(:establish_connection)
      Delayed::Backend::ActiveRecord::Job.after_fork
    end
  end

  describe "enqueue" do
    it "allows enqueue hook to modify job at DB level" do
      later = described_class.db_time_now + 20.minutes
      job = Delayed::Backend::ActiveRecord::Job.enqueue payload_object: EnqueueJobMod.new
      expect(Delayed::Backend::ActiveRecord::Job.find(job.id).run_at).to be_within(1).of(later)
    end
  end

  if ::ActiveRecord::VERSION::MAJOR < 4 || defined?(::ActiveRecord::MassAssignmentSecurity)
    context "ActiveRecord::Base.send(:attr_accessible, nil)" do
      before do
        Delayed::Backend::ActiveRecord::Job.send(:attr_accessible, nil)
      end

      after do
        Delayed::Backend::ActiveRecord::Job.send(:attr_accessible, *Delayed::Backend::ActiveRecord::Job.new.attributes.keys)
      end

      it "is still accessible" do
        job = Delayed::Backend::ActiveRecord::Job.enqueue payload_object: EnqueueJobMod.new
        expect(Delayed::Backend::ActiveRecord::Job.find(job.id).handler).to_not be_blank
      end
    end
  end

  context "ActiveRecord::Base.table_name_prefix" do
    it "when prefix is not set, use 'delayed_jobs' as table name" do
      ::ActiveRecord::Base.table_name_prefix = nil
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name

      expect(Delayed::Backend::ActiveRecord::Job.table_name).to eq "delayed_jobs"
    end

    it "when prefix is set, prepend it before default table name" do
      ::ActiveRecord::Base.table_name_prefix = "custom_"
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name

      expect(Delayed::Backend::ActiveRecord::Job.table_name).to eq "custom_delayed_jobs"

      ::ActiveRecord::Base.table_name_prefix = nil
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name
    end
  end
end
