require "./spec_helper"

private def build_session(id : Int64, host : String, started_at : Time, ended_at : Time? = nil) : Ping::MonitoringSession
  Ping::MonitoringSession.new(id, host, "spec-instance", started_at, ended_at)
end

describe Ping do
  it "keeps fixed-period send deadlines anchored to the configured interval" do
    started_at = Time.instant
    schedule = Ping::ICMPPinger::FixedPeriodSchedule.new(started_at, 1.second)

    schedule.remaining(started_at).should eq(0.seconds)
    schedule.mark_sent
    schedule.next_send_at.should eq(started_at + 1.second)
    schedule.remaining(started_at + 500.milliseconds).should eq(500.milliseconds)
    schedule.remaining(started_at + 1500.milliseconds).should eq(0.seconds)
    schedule.mark_sent
    schedule.next_send_at.should eq(started_at + 2.seconds)
  end

  it "tracks failure streaks and resets them on success" do
    history = Ping::HistoryStore.new(Ping::Settings.new)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    session = build_session(1_i64, "8.8.8.8", base)
    history.start_session(session)

    sample1 = history.add(Ping::SampleInput.new(base, 1, "timeout 1", false, nil, :timeout), session.id)
    sample2 = history.add(Ping::SampleInput.new(base + 1.second, 2, "timeout 2", false, nil, :timeout), session.id)
    sample3 = history.add(Ping::SampleInput.new(base + 2.seconds, 3, "ok", true, 12.0, :success), session.id)

    sample1.failure_streak.should eq(1)
    sample2.failure_streak.should eq(2)
    sample3.failure_streak.should eq(0)
  end

  it "fills chart columns with forward-fill from each sample to the next" do
    history = Ping::HistoryStore.new(Ping::Settings.new)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    session = build_session(1_i64, "8.8.8.8", base + 10.seconds, base + 1.minute)
    history.start_session(session)

    history.add(Ping::SampleInput.new(base + 10.seconds, 1, "ok", true, 11.0, :success), session.id)
    history.add(Ping::SampleInput.new(base + 30.seconds, 2, "timeout", false, nil, :timeout), session.id)
    history.add(Ping::SampleInput.new(base + 31.seconds, 3, "timeout", false, nil, :timeout), session.id)

    # 1-minute window, 6 columns => 10 s/column
    states = history.row_series(1.minute, 6, base + 1.minute).states

    states.size.should eq(6)
    states[0].should be_nil # before first ping: no data
    states[1].should eq(0)  # success at +10 s
    states[2].should eq(0)  # forward-filled from that success
    states[3].should eq(1)  # failures (streak <= 2) at +30 and +31 s
    states[4].should eq(1)  # forward-filled from those failures
  end

  it "stops filling columns after the provided stop time" do
    history = Ping::HistoryStore.new(Ping::Settings.new)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    session = build_session(1_i64, "8.8.8.8", base + 10.seconds, base + 25.seconds)
    history.start_session(session)

    history.add(Ping::SampleInput.new(base + 10.seconds, 1, "ok", true, 11.0, :success), session.id)

    states = history.row_series(1.minute, 6, base + 1.minute, base + 25.seconds).states

    states[0].should be_nil
    states[1].should eq(0)
    states[2].should eq(0)
    states[3].should be_nil
    states[4].should be_nil
    states[5].should be_nil
  end

  it "keeps stopped periods blank after monitoring resumes" do
    history = Ping::HistoryStore.new(Ping::Settings.new)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    session1 = build_session(1_i64, "8.8.8.8", base + 10.seconds, base + 25.seconds)
    session2 = build_session(2_i64, "8.8.8.8", base + 45.seconds, base + 1.minute)
    history.start_session(session1)
    history.start_session(session2)

    history.add(Ping::SampleInput.new(base + 10.seconds, 1, "ok", true, 11.0, :success), session1.id)
    history.add(Ping::SampleInput.new(base + 45.seconds, 2, "ok", true, 12.0, :success), session2.id)

    states = history.row_series(1.minute, 12, base + 1.minute).states

    states[2].should eq(0)
    states[5].should be_nil
    states[6].should be_nil
    states[9].should eq(0)
    states[10].should eq(0)
  end

  it "treats unfinished non-live sessions as ending at their last sample" do
    history = Ping::HistoryStore.new(Ping::Settings.new)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    crashed_session = build_session(1_i64, "8.8.8.8", base + 10.seconds)
    sample = Ping::Sample.new(crashed_session.id, base + 20.seconds, 1, "ok", true, 11.0, :success, 0)

    history.replace([crashed_session], [sample])

    states = history.row_series(1.minute, 6, base + 1.minute).states

    states[2].should eq(0)
    states[3].should be_nil
    states[4].should be_nil
    states[5].should be_nil
  end

  it "uses configurable thresholds for severity levels" do
    settings = Ping::Settings.new
    settings.warn_threshold = 1
    settings.alert_threshold = 3
    history = Ping::HistoryStore.new(settings)
    base = Time.utc(2026, 4, 1, 12, 0, 0)
    session = build_session(1_i64, "8.8.8.8", base + 10.seconds, base + 1.minute)
    history.start_session(session)

    history.add(Ping::SampleInput.new(base + 10.seconds, 1, "timeout 1", false, nil, :timeout), session.id)
    history.add(Ping::SampleInput.new(base + 20.seconds, 2, "timeout 2", false, nil, :timeout), session.id)
    history.add(Ping::SampleInput.new(base + 30.seconds, 3, "timeout 3", false, nil, :timeout), session.id)
    history.add(Ping::SampleInput.new(base + 40.seconds, 4, "timeout 4", false, nil, :timeout), session.id)

    states = history.row_series(1.minute, 6, base + 1.minute).states

    states[1].should eq(1)
    states[2].should eq(2)
    states[3].should eq(2)
    states[4].should eq(3)
  end
end
