module replatform64.nes.hardware;

///
enum Pad {
	right = 0x01, /// Right on the d-pad
	left = 0x02, /// Left on the d-pad
	down = 0x04, /// Down on the d-pad
	up = 0x08, /// Up on the d-pad
	start = 0x10, /// The start button in the centre
	select = 0x20, /// The select button in the centre
	b = 0x40, /// The left face button
	a = 0x80, /// The right face button
}
