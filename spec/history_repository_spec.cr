require "./spec_helper"

describe Ping::HistoryRepository do
  it "saves sessions and samples for a host" do
    path = File.tempname("ping-history-", ".sqlite3")
    repo = Ping::HistoryRepository.new(path)

    begin
      base = Time.utc(2026, 4, 3, 10, 0, 0)
      session = repo.create_session("8.8.8.8", "spec-instance", base)
      sample = Ping::Sample.new(session.id, base, 42, "ok", true, 11.5, :success, 0)
      repo.save_sample(session.id, sample)
      repo.close_session(session.id, base + 5.seconds)

      loaded_sessions, loaded_samples = repo.load_history("8.8.8.8", base - 1.minute)
      loaded_sessions.size.should eq(1)
      loaded_session = loaded_sessions.first
      loaded_session.id.should eq(session.id)
      loaded_session.instance_id.should eq("spec-instance")
      loaded_session.ended_at.should eq(base + 5.seconds)

      loaded_samples.size.should eq(1)
      loaded_sample = loaded_samples.first
      loaded_sample.session_id.should eq(session.id)
      loaded_sample.sequence.should eq(42)
      loaded_sample.raw_line.should eq("ok")
      loaded_sample.success?.should be_true
      loaded_sample.rtt_ms.should eq(11.5)
      loaded_sample.category.should eq(:success)
      loaded_sample.failure_streak.should eq(0)
    ensure
      repo.close
      File.delete(path) if File.exists?(path)
    end
  end
end
