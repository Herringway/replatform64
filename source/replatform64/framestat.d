module replatform64.framestat;

import core.time;
import std.algorithm.mutation;
import std.range;

static immutable frameStatisticLabels = ["Events", "Game logic", "Rendering"];
enum FrameStatistic {
	events,
	gameLogic,
	ppu,
}
struct Frame {
	MonoTime[2][FrameStatistic.max + 1] statistics;
	MonoTime start;
	MonoTime end;
}
struct FrameStatTracker {
	enum frameCount = 60;
	Frame[frameCount] history;
	private Frame next;
	private MonoTime lastCheck;
	void startFrame() @safe {
		auto now = MonoTime.currTime;
		lastCheck = now;
		next.start = now;
	}
	void checkpoint(FrameStatistic stat) @safe {
		auto now = MonoTime.currTime;
		next.statistics[stat] = [lastCheck, now];
		lastCheck = now;
	}
	void endFrame() @safe {
		next.end = MonoTime.currTime;
		copy(history[1 .. $].chain(only(next)), history[]);
	}
}

FrameStatTracker frameStatTracker;
