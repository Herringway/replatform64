module replatform64.framestat;

enum FrameStatistic {
	gameLogic,
	events,
	renderer,
	overlay,
	imgui,
	ppu,
}
struct FrameStatTracker {
	import core.time : Duration, MonoTime;
	MonoTime[2][FrameStatistic.max + 1] frameStatistics;
	private MonoTime[2][FrameStatistic.max + 1] frameStatisticsNextFrame;
	private MonoTime lastCheck;
	MonoTime frameStart;
	MonoTime frameEnd;
	private MonoTime nextFrameStart;
	void startFrame() {
		lastCheck = MonoTime.currTime;
		nextFrameStart = lastCheck;
	}
	void checkpoint(FrameStatistic stat) {
		auto now = MonoTime.currTime();
		frameStatisticsNextFrame[stat] = [lastCheck, now];
		lastCheck = now;
	}
	void endFrame() {
		frameEnd = MonoTime.currTime();
		frameStatistics = frameStatisticsNextFrame;
		frameStart = nextFrameStart;
	}
}

FrameStatTracker frameStatTracker;
