require 'helper'
require 'delayed/backend/active_record'

describe Delayed::Backend::ActiveRecord::Job do
  it_behaves_like 'a delayed_job backend'

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

  describe '.clear_lock!' do
    let(:deadlock_error) do
      # The exception will be an ActiveRecord::StatementInvalid, but we can
      # avoid making a new dependency on that class by just checking the message here.
      StandardError.new("Exception: Mysql2::Error: Deadlock found when trying to get lock; try restarting transaction: <transaction details>")
    end
    
    context "when an unrecoverable deadlock" do

      it "will retry 10 times and then raise the exception" do
        Delayed::Job.should_receive(:by_locked).with('name').exactly(11).times.and_raise deadlock_error

        expect do
          Delayed::Job.clear_locks!('name')
        end.to raise_error(deadlock_error)

      end
    end

    context "when a recoverable deadlock" do
      it "will retry 9 times and then pass" do
        Delayed::Job.should_receive(:by_locked).with('name').exactly(10).times.and_raise deadlock_error

        Delayed::Job.should_receive(:by_locked).with('name').and_return(
          double(:records, :update_all => true)
        )

        Delayed::Job.clear_locks!('name')
      end
    end
  end

  context "db_time_now" do
    after do
      Time.zone = nil
      ActiveRecord::Base.default_timezone = :local
    end

    it "returns time in current time zone if set" do
      Time.zone = 'Eastern Time (US & Canada)'
      expect(%(EST EDT)).to include(Delayed::Job.db_time_now.zone)
    end

    it "returns UTC time if that is the AR default" do
      Time.zone = nil
      ActiveRecord::Base.default_timezone = :utc
      expect(Delayed::Backend::ActiveRecord::Job.db_time_now.zone).to eq 'UTC'
    end

    it "returns local time if that is the AR default" do
      Time.zone = 'Central Time (US & Canada)'
      ActiveRecord::Base.default_timezone = :local
      expect(%w(CST CDT)).to include(Delayed::Backend::ActiveRecord::Job.db_time_now.zone)
    end
  end

  describe "after_fork" do
    it "calls reconnect on the connection" do
      ActiveRecord::Base.should_receive(:establish_connection)
      Delayed::Backend::ActiveRecord::Job.after_fork
    end
  end

  describe "enqueue" do
    it "allows enqueue hook to modify job at DB level" do
      later = described_class.db_time_now + 20.minutes
      job = Delayed::Backend::ActiveRecord::Job.enqueue :payload_object => EnqueueJobMod.new
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
        job = Delayed::Backend::ActiveRecord::Job.enqueue :payload_object => EnqueueJobMod.new
        expect(Delayed::Backend::ActiveRecord::Job.find(job.id).handler).to_not be_blank
      end
    end
  end

  context "ActiveRecord::Base.table_name_prefix" do
    it "when prefix is not set, use 'delayed_jobs' as table name" do
      ::ActiveRecord::Base.table_name_prefix = nil
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name

      expect(Delayed::Backend::ActiveRecord::Job.table_name).to eq 'delayed_jobs'
    end

    it "when prefix is set, prepend it before default table name" do
      ::ActiveRecord::Base.table_name_prefix = 'custom_'
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name

      expect(Delayed::Backend::ActiveRecord::Job.table_name).to eq 'custom_delayed_jobs'

      ::ActiveRecord::Base.table_name_prefix = nil
      Delayed::Backend::ActiveRecord::Job.set_delayed_job_table_name
    end
  end
end
