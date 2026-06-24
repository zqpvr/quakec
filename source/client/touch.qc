/*
	touch.qc -- on-screen touch controls

	The action-button artwork (gfx/touch/btn_*) is from glKarin's Diii4a /
	idTech4A++ Android engine (github.com/glKarin/com.n0n3m4.diii4a), GPL-3.0,
	same license family as this tree. The movement-stick ring/knob are ours.

	Layout: a floating movement stick under the left thumb, look-drag under the
	right thumb, and a column of action buttons down the right edge. Everything
	here only runs while actually in a game -- menus and the pause screen are
	left completely alone, and the controller path is never touched.
*/

// touch keycodes as the engine reports them to CSQC (keys.h enum; confirmed on-device)
#define K_TOUCH       600
#define K_TOUCHSLIDE  601
#define K_TOUCHTAP    602
#define K_TOUCHLONG   603

// action buttons -- ADS-fire is the one and only shoot button now
#define TB_ADSFIRE  0	// hold to aim down sights, then fire (CoD-mobile style)
#define TB_RELOAD   1
#define TB_KNIFE    2
#define TB_GRENADE  3
#define TB_USE      4
#define TB_SWAP     5
#define TB_JUMP     6
#define TB_CROUCH   7	// stance toggle, or dolphin dive while sprinting
#define TB_BETTY    8	// prime a Bouncing Betty
#define TB_NADESWAP 9	// cycle grenade type (frag <-> monkey bomb)
#define TB_PAUSE    10
#define TB_COUNT    11
// no sprint button: running is automatic, see Touch_Frame

// per-finger roles
#define TR_NONE  0
#define TR_MOVE  1
#define TR_LOOK  2
#define TR_BTN   3

#define TOUCH_MAXFINGERS 10

float touch_active[TOUCH_MAXFINGERS];
float touch_role[TOUCH_MAXFINGERS];
float touch_curx[TOUCH_MAXFINGERS];
float touch_cury[TOUCH_MAXFINGERS];
float touch_orgx[TOUCH_MAXFINGERS];	// stick origin, or look last-pos
float touch_orgy[TOUCH_MAXFINGERS];
float touch_btn[TOUCH_MAXFINGERS];

// movement + look handed to CSQC_Input_Frame
float touch_move_on;
float touch_move_fwd, touch_move_side;
float touch_look_dyaw, touch_look_dpitch;

// fire / aim resolution
float touch_ads_was;		// was the ADS-fire button held last frame
float touch_ads_start;		// cltime the ADS-fire press began (for the aim-then-fire delay)
float touch_sniper_armed;	// scoped sniper held -- fire on release ("quickscope")
float touch_sniper_fire_until;	// hold the shot briefly after a sniper release
float touch_sprinting;		// auto-run state, so the stop impulse only fires on a change
float touch_sprint_retry;	// cltime the sprint request may be repeated at
float touch_sprint_since;	// cltime running was first wanted, 0 when it is not
float touch_sprint_stopping;	// cltime running stopped being wanted, 0 while it is
vector touch_sprint_org;	// view origin when running was first wanted


// geometry of action button 'id' -> [centre_x, centre_y, size]
vector(float id) Touch_BtnGeom =
{
	float w = g_width, h = g_height, b = h * 0.13;
	// combat buttons cluster on the right; movement-ish ones sit by the left thumb,
	// and the centre stays open for look-drag
	switch (id) {
		case TB_ADSFIRE:  return [w * 0.87, h * 0.83, b * 1.35];	// main shoot button
		case TB_RELOAD:   return [w * 0.75, h * 0.87, b * 0.95];
		case TB_KNIFE:    return [w * 0.92, h * 0.58, b * 0.90];
		case TB_USE:      return [w * 0.79, h * 0.58, b * 0.90];
		case TB_GRENADE:  return [w * 0.92, h * 0.38, b * 0.90];
		case TB_JUMP:     return [w * 0.79, h * 0.38, b * 0.90];
		case TB_SWAP:     return [w * 0.92, h * 0.19, b * 0.85];
		case TB_BETTY:    return [w * 0.79, h * 0.19, b * 0.85];
		case TB_NADESWAP: return [w * 0.67, h * 0.19, b * 0.75];
		// left thumb reaches these without leaving the stick
		case TB_CROUCH:   return [w * 0.29, h * 0.85, b * 0.90];
		case TB_PAUSE:    return [w * 0.035, h * 0.11, b * 0.62];
	}
	return '0 0 0';
};

string(float id) Touch_BtnPic =
{
	switch (id) {
		case TB_ADSFIRE:  return "gfx/touch/touch_adsfire";	// aim + fire
		case TB_RELOAD:   return "gfx/touch/btn_reload";
		case TB_KNIFE:    return "gfx/touch/touch_knife";
		case TB_GRENADE:  return "gfx/touch/touch_grenade";
		case TB_USE:      return "gfx/touch/btn_activate";	// hand = use / buy
		case TB_SWAP:     return "gfx/touch/touch_swap";
		case TB_JUMP:     return "gfx/touch/btn_jump";
		case TB_CROUCH:   return "gfx/touch/touch_crouch";
		case TB_BETTY:    return "gfx/touch/touch_betty";
		case TB_NADESWAP: return "gfx/touch/touch_nadeswap";
		case TB_PAUSE:    return "gfx/touch/touch_pause";
	}
	return "";
};

void(float id) Touch_BtnPress =
{
	switch (id) {
		case TB_ADSFIRE:  break;	// shooting is resolved in Touch_Frame
		case TB_RELOAD:   localcmd("+button5\n");   break;
		case TB_KNIFE:    localcmd("+button6\n");   break;
		case TB_GRENADE:  localcmd("+button3\n");   break;
		case TB_USE:      localcmd("+button7\n");   break;
		case TB_SWAP:     localcmd("+button4\n");   break;
		case TB_JUMP:     localcmd("impulse 10\n"); break;
		case TB_CROUCH:   localcmd("impulse 30\n"); break;	// stance / dolphin dive
		case TB_BETTY:    localcmd("impulse 33\n"); break;	// prime a Bouncing Betty
		case TB_NADESWAP: localcmd("impulse 25\n"); break;	// frag <-> monkey bomb
		case TB_PAUSE:    localcmd("togglemenu\n"); break;
	}
};

void(float id) Touch_BtnRelease =
{
	switch (id) {
		case TB_RELOAD:  localcmd("-button5\n");  break;
		case TB_KNIFE:   localcmd("-button6\n");  break;
		case TB_GRENADE: localcmd("-button3\n");  break;
		case TB_USE:     localcmd("-button7\n");  break;
		case TB_SWAP:    localcmd("-button4\n");  break;
		// ADSFIRE / JUMP / CROUCH / BETTY / NADESWAP / PAUSE: one-shot, nothing to release
	}
};

// which button (if any) sits under (x, y); -1 for none. hit area padded slightly.
float(float x, float y) Touch_HitButton =
{
	float i;
	for (i = 0; i < TB_COUNT; i = i + 1) {
		vector bg = Touch_BtnGeom(i);
		float hs = bg_z * 0.5 * 1.15;
		if (x >= bg_x - hs && x <= bg_x + hs && y >= bg_y - hs && y <= bg_y + hs)
			return i;
	}
	return -1;
};

// does some finger other than 'devid' already own the movement stick?
float(float devid) Touch_StickTaken =
{
	float i;
	for (i = 0; i < TOUCH_MAXFINGERS; i = i + 1)
		if (i != devid && touch_active[i] && touch_role[i] == TR_MOVE)
			return TRUE;
	return FALSE;
};

// is action 'id' currently held by a finger? (for the press highlight)
float(float id) Touch_BtnHeld =
{
	float i;
	for (i = 0; i < TOUCH_MAXFINGERS; i = i + 1)
		if (touch_active[i] && touch_role[i] == TR_BTN && touch_btn[i] == id)
			return TRUE;
	return FALSE;
};

void(float devid) Touch_FingerUp =
{
	if (!touch_active[devid])
		return;
	if (touch_role[devid] == TR_BTN)
		Touch_BtnRelease(touch_btn[devid]);
	else if (touch_role[devid] == TR_MOVE) {
		touch_move_on = FALSE;
		touch_move_fwd = 0;
		touch_move_side = 0;
	}
	touch_active[devid] = FALSE;
	touch_role[devid] = TR_NONE;
};

void(float devid, float x, float y) Touch_FingerMove =
{
	touch_curx[devid] = x;
	touch_cury[devid] = y;

	if (touch_role[devid] == TR_NONE) {
		// first sample after touch-down decides what this finger is for
		float bid = Touch_HitButton(x, y);
		if (bid >= 0) {
			touch_role[devid] = TR_BTN;
			touch_btn[devid] = bid;
			touch_orgx[devid] = x;	// so fire/ads-fire can double as a look pad
			touch_orgy[devid] = y;
			Touch_BtnPress(bid);
			return;
		} else if (x < g_width * 0.42 && !Touch_StickTaken(devid)) {
			// Only one finger drives the stick. A second one landing on this side
			// would otherwise re-anchor it under itself, and since the deflection
			// is measured from the anchor the movement would drop to nothing while
			// the first thumb was still pushing.
			touch_role[devid] = TR_MOVE;
			touch_move_on = TRUE;
			touch_orgx[devid] = x;	// the stick anchors where the thumb lands
			touch_orgy[devid] = y;
			// fall through and engage straight away
		} else {
			touch_role[devid] = TR_LOOK;
			touch_orgx[devid] = x;
			touch_orgy[devid] = y;
			return;
		}
	}

	if (touch_role[devid] == TR_MOVE) {
		// The stick is anchored wherever the thumb landed, not at one fixed spot on
		// the screen. Measuring from a fixed centre meant that simply putting a thumb
		// down away from it was already a full-tilt shove in whatever direction it
		// happened to sit -- you had to land inside one small circle or run off
		// somewhere you never asked to go. The anchor stays put for the whole touch,
		// so it can't creep across the screen while held either.
		float radius = g_height * 0.16;
		float dx = x - touch_orgx[devid], dy = y - touch_orgy[devid];
		float mag = sqrt(dx * dx + dy * dy);

		if (mag > radius && mag > 0) { dx = dx * (radius / mag); dy = dy * (radius / mag); }

		touch_curx[devid] = touch_orgx[devid] + dx;	// clamped knob position, for drawing
		touch_cury[devid] = touch_orgy[devid] + dy;

		if (mag < radius * 0.12) {	// a resting thumb is not an input
			touch_move_fwd = 0;
			touch_move_side = 0;
		} else {
			float fspeed = cvar("cl_forwardspeed"); if (fspeed <= 0) fspeed = 400;
			float sspeed = cvar("cl_sidespeed");    if (sspeed <= 0) sspeed = 400;
			touch_move_fwd  = (-dy / radius) * fspeed;	// up on screen = forward
			touch_move_side = ( dx / radius) * sspeed;
		}
	}
	else if (touch_role[devid] == TR_LOOK) {
		float sens = cvar("touch_looksens"); if (sens <= 0) sens = 0.35;
		float lx = x - touch_orgx[devid];
		float ly = y - touch_orgy[devid];
		touch_look_dyaw   = touch_look_dyaw   - lx * sens;	// drag right = look right
		touch_look_dpitch = touch_look_dpitch + ly * sens;	// drag down = look down (+x=down)
		touch_orgx[devid] = x;
		touch_orgy[devid] = y;
	}
	else if (touch_role[devid] == TR_BTN) {
		// the shoot button doubles as a look pad: drag off it to aim while firing
		if (touch_btn[devid] == TB_ADSFIRE) {
			float bsens = cvar("touch_looksens"); if (bsens <= 0) bsens = 0.35;
			touch_look_dyaw   = touch_look_dyaw   - (x - touch_orgx[devid]) * bsens;
			touch_look_dpitch = touch_look_dpitch + (y - touch_orgy[devid]) * bsens;
			touch_orgx[devid] = x;
			touch_orgy[devid] = y;
		}
	}
};

void() CSQC_MenuBack;	// defined further down in main.qc

/*
	Pause / in-game menu support.

	sui only counts K_MOUSE1 as a click, but a touchscreen reports K_TOUCH, so the
	menu was unusable: the cursor followed your finger yet nothing could be picked.
	Translate touch into the mouse events sui already understands. The touch-down
	arrives *before* the first position sample, so the click is held back until we
	know where the finger actually landed -- otherwise it would click whatever the
	cursor happened to be over beforehand.
*/
float touch_menu_pending[TOUCH_MAXFINGERS];	// finger down, waiting on a position
float touch_menu_down[TOUCH_MAXFINGERS];	// we issued a mouse1-down for this finger

// on-screen back button, tucked in the top-left while a menu is open
vector() Touch_MenuBackGeom =
{
	float b = g_height * 0.13;
	return [g_width * 0.05, g_height * 0.12, b * 0.85];
};

float(float evtype, float scanx, float chary, float devid) Touch_MenuEvent =
{
	if (devid < 0 || devid >= TOUCH_MAXFINGERS)
		return FALSE;

	if (evtype == IE_KEYDOWN && scanx == K_TOUCH) {
		touch_menu_pending[devid] = TRUE;
		return TRUE;
	}

	if (evtype == IE_KEYUP && scanx == K_TOUCH) {
		if (touch_menu_down[devid]) {
			sui_input_event(IE_KEYUP, K_MOUSE1, 0, devid);
			touch_menu_down[devid] = FALSE;
		}
		touch_menu_pending[devid] = FALSE;
		return TRUE;
	}

	// swallow the slide/tap/long companions so they don't reach the text input buffer
	if ((evtype == IE_KEYDOWN || evtype == IE_KEYUP) &&
	    (scanx == K_TOUCHSLIDE || scanx == K_TOUCHTAP || scanx == K_TOUCHLONG))
		return TRUE;

	if (evtype == IE_MOUSEABS) {
		sui_input_event(IE_MOUSEABS, scanx, chary, devid);	// move the cursor first
		if (touch_menu_pending[devid]) {
			touch_menu_pending[devid] = FALSE;

			vector bb = Touch_MenuBackGeom();
			float hs = bb_z * 0.5 * 1.2;
			if (scanx >= bb_x - hs && scanx <= bb_x + hs &&
			    chary >= bb_y - hs && chary <= bb_y + hs) {
				CSQC_MenuBack();
				return TRUE;
			}

			sui_input_event(IE_KEYDOWN, K_MOUSE1, 0, devid);
			touch_menu_down[devid] = TRUE;
		}
		return TRUE;
	}

	return FALSE;	// leave keyboard/controller events to the normal menu path
};

void() Touch_DrawMenuBack =
{
	if (last_input_was_gamepad)
		return;
	vector bb = Touch_MenuBackGeom();
	drawpic([bb_x - bb_z * 0.5, bb_y - bb_z * 0.5, 0], "gfx/touch/touch_back", [bb_z, bb_z], [1, 1, 1], 0.55);
};

// returns TRUE when it handled (and so consumes) the event
float(float evtype, float scanx, float chary, float devid) Touch_InputEvent =
{
	if (current_menu != MENU_NONE)
		return Touch_MenuEvent(evtype, scanx, chary, devid);
	if (devid < 0 || devid >= TOUCH_MAXFINGERS)
		return FALSE;

	if (evtype == IE_KEYDOWN && scanx == K_TOUCH) {
		touch_active[devid] = TRUE;
		touch_role[devid] = TR_NONE;	// assigned on the first position sample
		return TRUE;
	}
	if (evtype == IE_KEYUP && scanx == K_TOUCH) {
		Touch_FingerUp(devid);
		return TRUE;
	}
	if ((evtype == IE_KEYDOWN || evtype == IE_KEYUP) &&
	    (scanx == K_TOUCHSLIDE || scanx == K_TOUCHTAP || scanx == K_TOUCHLONG))
		return TRUE;	// swallow the slide/tap companions

	if (evtype == IE_MOUSEABS) {
		// only track fingers that are genuinely down. the engine emits a trailing
		// position sample *after* the touch-up; honouring that would re-engage a
		// finger that was just released (stuck stick / look).
		if (touch_active[devid])
			Touch_FingerMove(devid, scanx, chary);
		return TRUE;
	}
	if (evtype == IE_MOUSEDELTA)
		return TRUE;

	return FALSE;
};

// Is the viewmodel currently inside the given animation? Weapons that lack one
// report a start of zero or an end before the start, which would otherwise match
// every frame and read as permanently mid-animation.
float(float wep, float startidx, float endidx, float frame) Touch_FrameInAnim =
{
	float s = GetFrame(wep, startidx);
	float e = GetFrame(wep, endidx);

	if (s <= 0 || e < s)
		return FALSE;

	return (frame >= s && frame <= e);
};

// scoped bolt-action snipers -- aim, then fire on release, and never fire mid-scope
float(float wep) Touch_IsSniper =
{
	float base = EqualNonPapWeapon(wep);
	return (base == W_KAR_SCOPE || base == W_PTRS || wep == W_HEADCRACKER);
};

// fold movement + look into this frame's command. called first in CSQC_Input_Frame
// so weapon kick/sway still layer on top. left untouched while a controller is in use.
void() Touch_Frame =
{
	if (last_input_was_gamepad)
		return;	// controller owns input -- stay completely out of the way

	// guard against a dropped touch-up leaving the player walking by itself
	float fi, moving = FALSE;
	for (fi = 0; fi < TOUCH_MAXFINGERS; fi = fi + 1)
		if (touch_active[fi] && touch_role[fi] == TR_MOVE) { moving = TRUE; break; }
	if (!moving) { touch_move_on = FALSE; touch_move_fwd = 0; touch_move_side = 0; }

	// --- shooting: the ADS-fire button is the only shoot button now ---
	float bi, adsfire_held = FALSE;
	for (bi = 0; bi < TOUCH_MAXFINGERS; bi = bi + 1)
		if (touch_active[bi] && touch_role[bi] == TR_BTN && touch_btn[bi] == TB_ADSFIRE)
			adsfire_held = TRUE;

	if (adsfire_held && !touch_ads_was)
		touch_ads_start = cltime;

	// 0 = hip, 1 = ADS, 2 = scoped sniper, 3 = sprinting. That last one is not a
	// zoom at all -- the server parks its sprint state in the same field.
	float wz = getstatf(STAT_WEAPONZOOM);
	float aiming = (wz == 1 || wz == 2);
	float actwep = getstatf(STAT_ACTIVEWEAPON);
	float firetype = GetFiretype(EqualNonPapWeapon(actwep));

	// fire behaviour by weapon:
	//   release-fire (aim, shoot on let-go): scoped snipers + rocket launchers
	//   hold (continuous):                   full-autos, tesla, flamethrower
	//   tap  (one shot per deliberate press): semi, grenade, blade, ray, everything else
	float is_release = Touch_IsSniper(actwep) || firetype == FIRETYPE_ROCKET;
	float is_hold    = (firetype == FIRETYPE_FULLAUTO || firetype == FIRETYPE_TESLA || firetype == FIRETYPE_FLAME);

	// weapons with sights wait a beat so they don't fire mid-raise; weapons without
	// (tesla, ray, ballistic knife, flamethrower...) fire the instant you press
	float weapon_adses = (firetype == FIRETYPE_SEMIAUTO || firetype == FIRETYPE_FULLAUTO || is_release);
	float settle = weapon_adses ? 0.12 : 0;
	float fire_ok = adsfire_held && (cltime - touch_ads_start) >= settle;

	if (adsfire_held)
		input_buttons = input_buttons | 128;	// hold ADS (a no-op for non-sighted weapons)

	if (is_release) {
		if (adsfire_held)
			touch_sniper_armed = TRUE;	// never fire while held -- wait for the release
	} else if (fire_ok) {
		if (is_hold) {
			input_buttons = input_buttons | 1;	// continuous
		} else {
			// semi / grenade / blade / ray: tap at a deliberate rate, not machine-gun fast
			float ph = cltime - floor(cltime / 0.25) * 0.25;
			if (ph < 0.05)
				input_buttons = input_buttons | 1;
		}
	}

	// release shot for snipers + rockets ("aim, then let go"); a quick tap fires from the hip
	if (touch_ads_was && !adsfire_held && touch_sniper_armed) {
		touch_sniper_fire_until = cltime + 0.10;
		touch_sniper_armed = FALSE;
	}
	if (cltime < touch_sniper_fire_until)
		input_buttons = input_buttons | 129;	// attack (1) + ADS (128) so the shot lands true

	touch_ads_was = adsfire_held;

	// look: rotate the *actual* client viewangles (the camera). modifying only
	// input_angles turns the outgoing command but leaves the camera frozen, which
	// also makes movement run relative to a different angle than you can see.
	// sensitivity drops while aiming, and drops further through a sniper scope.
	if (touch_look_dyaw || touch_look_dpitch) {
		float lookmul = 1;
		if (wz == 1)      lookmul = 0.55;	// ADS
		else if (wz == 2) lookmul = 0.35;	// scoped sniper
		if (getstatf(STAT_FACINGENEMY))		// aim-assist slowdown when on a target
			lookmul = lookmul * 0.5;
		vector va = getproperty(VF_CL_VIEWANGLES);
		va_y = va_y + touch_look_dyaw * lookmul;
		va_x = va_x + touch_look_dpitch * lookmul;
		if (va_x >  89) va_x =  89;
		if (va_x < -89) va_x = -89;
		setproperty(VF_CL_VIEWANGLES, va);
		input_angles_x = va_x;	// keep this frame's command in step with the view
		input_angles_y = va_y;
		touch_look_dyaw = 0;
		touch_look_dpitch = 0;
	}

	// movement
	if (touch_move_on) {
		input_movevalues_x = input_movevalues_x + touch_move_fwd;
		input_movevalues_y = input_movevalues_y + touch_move_side;
	}

	// Auto-run: push the stick forward and you sprint, no button for it. The
	// server drives sprinting off impulses rather than a held button, so only
	// send one when the state actually changes -- otherwise it restarts the
	// sprint every frame. Aiming drops back to a walk, as it does elsewhere.
	// A wide forward arc counts, not just dead ahead: anything in the forward
	// half of the stick runs, so angling around a corner doesn't drop you to a
	// walk. Only a real sideways or backward push stops it.
	// Starting a sprint throws away a reload in progress -- the server clears the
	// reload timers as it stands the player up -- so wait for it to finish rather
	// than silently costing the player the magazine they asked for.
	float wframe = getstatf(STAT_WEAPONFRAME);
	float reloading = Touch_FrameInAnim(actwep, RELOAD_START,       RELOAD_END,       wframe)
	               || Touch_FrameInAnim(actwep, RELOAD_EMPTY_START, RELOAD_EMPTY_END, wframe)
	               || Touch_FrameInAnim(actwep, RELOAD_PART_START,  RELOAD_PART_END,  wframe);

	float fwd_ref = cvar("cl_forwardspeed"); if (fwd_ref <= 0) fwd_ref = 400;
	float want_sprint = touch_move_on
	                 && touch_move_fwd > fwd_ref * 0.2
	                 && touch_move_fwd > fabs(touch_move_side) * 0.2
	                 && !aiming	// walk while aiming, but 3 means we are already running
	                 && !reloading;

	// The server discards a sprint request that arrives before the player is
	// actually moving forward, and stops sprinting by itself once stamina runs
	// out, so one impulse on the way in is not enough to keep running. Re-ask
	// while we still want to, but only while it is not already happening
	// (zoom 3), and slowly enough not to flood a server with impulses.
	// The server takes the request, then cancels the sprint on the very next frame
	// if the player has not got moving yet -- and that dead start costs a full
	// second of cooldown, during which every retry is refused too. Asking while
	// still stationary therefore buys a second of walking, which is exactly what
	// dragging the stick from rest used to do.
	//
	// pmove_vel cannot be used to tell whether that has happened: it reads zero,
	// because it does not report for a csqc-owned entity. Per-frame movement of the
	// view is no better -- it swings between a crawl and hundreds of units in
	// consecutive frames. Distance covered since running was first wanted is steady,
	// and is the thing the server is really asking about.
	vector vorg = getproperty(VF_ORIGIN);

	if (!want_sprint) {
		touch_sprint_since = 0;
	} else if (!touch_sprint_since) {
		touch_sprint_since = cltime;
		touch_sprint_org = vorg;	// where we were when running was first wanted
	}

	vector moved = vorg - touch_sprint_org;
	moved_z = 0;
	float rolling = touch_sprint_since && vlen(moved) > 60;

	if (want_sprint) {
		if (wz != 3 && rolling && cltime > touch_sprint_retry) {
			localcmd("impulse 23\n");
			touch_sprint_retry = cltime + 0.25;
		}
	} else if (touch_sprinting) {
		// Don't act on a single frame of not wanting it. A thumb that lifts and
		// lands again re-anchors the stick, so deflection reads as nothing for a
		// frame or two even though the player never stopped pushing; stopping on
		// that costs a second of cooldown and the run dies for no reason.
		if (!touch_sprint_stopping)
			touch_sprint_stopping = cltime;

		if (cltime - touch_sprint_stopping > 0.2) {
			localcmd("impulse 24\n");
			touch_sprinting = FALSE;
			touch_sprint_stopping = 0;
		}
	}

	if (want_sprint) {
		touch_sprinting = TRUE;
		touch_sprint_stopping = 0;
	}

};

void() Touch_DrawStick =
{
	float i, finger = -1;
	for (i = 0; i < TOUCH_MAXFINGERS; i = i + 1)
		if (touch_active[i] && touch_role[i] == TR_MOVE) { finger = i; break; }

	// The base follows the anchor, so it appears under the thumb rather than
	// sitting somewhere the thumb has to find. With nothing held it rests at the
	// usual spot as a hint of where the stick lives.
	float scx = g_width * 0.15, scy = g_height * 0.74;
	float base = g_height * 0.34, knob = g_height * 0.15;
	float kx = scx, ky = scy, ba = 0.16, ka = 0.22;
	if (finger >= 0) {
		scx = touch_orgx[finger];
		scy = touch_orgy[finger];
		kx = touch_curx[finger];
		ky = touch_cury[finger];
		ba = 0.30;
		ka = 0.45;
	}
	drawpic([scx - base * 0.5, scy - base * 0.5, 0], "gfx/touch/stick_base", [base, base], [1, 1, 1], ba);
	drawpic([kx - knob * 0.5, ky - knob * 0.5, 0], "gfx/touch/stick_knob", [knob, knob], [1, 1, 1], ka);
};

void() Touch_DrawControls =
{
	if (current_menu != MENU_NONE)
		return;
	if (last_input_was_gamepad)	// controller in use -- hide the on-screen pad
		return;

	Touch_DrawStick();

	float i;
	for (i = 0; i < TB_COUNT; i = i + 1) {
		vector bg = Touch_BtnGeom(i);
		float lit = Touch_BtnHeld(i);
		drawpic([bg_x - bg_z * 0.5, bg_y - bg_z * 0.5, 0], Touch_BtnPic(i), [bg_z, bg_z], [1, 1, 1], lit ? 0.75 : 0.40);
	}
};
