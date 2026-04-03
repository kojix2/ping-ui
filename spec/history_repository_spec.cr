require "./spec_helper"

describe Ping::HistoryRepository do
  it "saves and loads samples for a host" do
    path = File.tempname("ping-history-", ".sqlite3")
    repo = Ping::HistoryRepository.new(path)

    begin
      base = Time.utc(2026, 4, 3, 10, 0, 0)
      sample = Ping::Sample.new(base, 42, "ok", true, 11.5, :success, 0)
      repo.save_sample("8.8.8.8", sample)

      loaded = repo.load_samples("8.8.8.8", base - 1.minute)
      loaded.size.should eq(1)
      loaded_sample = loaded.first
      loaded_sample.sequence.should eq(42)
      loaded_sample.raw_line.should eq("ok")
      loaded_sample.success.should eq(true)
      loaded_sample.rtt_ms.should eq(11.5)
      loaded_sample.category.should eq(:success)
      loaded_sample.failure_streak.should eq(0)
    ensure
      repo.close
      File.delete(path) if File.exists?(path)
    end
  end
end
