/*
	menu_vadv.qc -- advanced video options

	The main video menu is full (its rows are laid out at fixed 25px steps with no
	scrolling), so the heavier graphics knobs live here. These matter most on phones,
	where render scale and the effect toggles are the difference between 30 and 60fps.

	The first row is the big one. FTE carries a full realtime lighting pipeline that
	NZ:P never switches on, because the maps are lit the old way -- light values baked
	into lightmaps at compile time, with the light entities left behind as dead data.
	Turning it on hands those entities back to the renderer as real lights: every lamp
	and spotlight becomes an actual light source, geometry casts shadows from it, and
	the muzzle flash throws the room around as you fire. All nineteen shipped maps
	still carry their light entities, and ndu has a sun and ten spotlights among them.
*/

string menu_vadv_buttons[10] = {"va_hiend", "va_scale", "va_aniso", "va_dynlt", "va_bloom",
                                "va_fsky", "va_vmodel", "va_bob", "va_brite", "va_back"};

float menu_vadv_init;

float current_va_hiend;
float current_va_dynlt;
float current_va_bloom;
float current_va_fsky;
float current_va_vmodel;
float current_va_bob;

void() Menu_VideoAdv_Init =
{
	current_va_hiend  = cvar("r_shadow_realtime_world") != 0;
	current_va_dynlt  = cvar("r_dynamic") != 0;
	current_va_bloom  = cvar("r_bloom") != 0;
	current_va_fsky   = cvar("r_fastsky") != 0;
	current_va_vmodel = cvar("r_drawviewmodel") != 0;
	current_va_bob    = cvar("cl_bob") != 0;

	menu_vadv_init = true;
};

//
// Menu_VideoAdv_ToggleHighEnd()
// Switches the renderer between NZ:P's baked lighting and FTE's realtime pipeline.
// Specular and offset mapping ride along because neither does anything without a
// real light to react to.
//
void() Menu_VideoAdv_ToggleHighEnd =
{
	current_va_hiend = !current_va_hiend;

	if (current_va_hiend) {
		// build lights out of the map's own entity lump -- 0 would mean explicit
		// .rtlight files only, which NZ:P does not ship
		cvar_set("r_shadow_realtime_world_importlightentitiesfrommap", "1");
		cvar_set("r_shadow_realtime_world", "1");
		cvar_set("r_shadow_realtime_world_shadows", "1");

		// keep a quarter of the baked lightmap underneath. The maps were lit for
		// it, and without a floor of ambience the corners they never placed a lamp
		// in go black.
		cvar_set("r_shadow_realtime_world_lightmaps", "0.25");

		cvar_set("r_shadow_realtime_dlight", "1");
		cvar_set("r_shadow_realtime_dlight_shadows", "1");
		cvar_set("r_shadow_shadowmapping", "1");	// soft maps rather than stencil
		cvar_set("r_shadow_playershadows", "1");

		cvar_set("gl_specular", "1");
		cvar_set("r_glsl_offsetmapping", "1");
	} else {
		cvar_set("r_shadow_realtime_world", "0");
		cvar_set("r_shadow_realtime_world_importlightentitiesfrommap", "0");
		cvar_set("r_shadow_realtime_world_lightmaps", "0");
		cvar_set("gl_specular", "0.3");			// engine default
		cvar_set("r_glsl_offsetmapping", "0");
	}
};

void() Menu_VideoAdv_ToggleDynamic =
{
	current_va_dynlt = !current_va_dynlt;
	cvar_set("r_dynamic", current_va_dynlt ? "1" : "0");
};

void() Menu_VideoAdv_ToggleBloom =
{
	current_va_bloom = !current_va_bloom;
	cvar_set("r_bloom", current_va_bloom ? "1" : "0");
};

void() Menu_VideoAdv_ToggleFastSky =
{
	current_va_fsky = !current_va_fsky;
	cvar_set("r_fastsky", current_va_fsky ? "1" : "0");
};

void() Menu_VideoAdv_ToggleViewmodel =
{
	current_va_vmodel = !current_va_vmodel;
	cvar_set("r_drawviewmodel", current_va_vmodel ? "1" : "0");
};

void() Menu_VideoAdv_ToggleBob =
{
	current_va_bob = !current_va_bob;
	cvar_set("cl_bob", current_va_bob ? "0.02" : "0");
};

string(string prev_id) Menu_VideoAdv_GetNextButton =
{
	if (prev_id == "")
		return menu_vadv_buttons[0];

	string ret = menu_vadv_buttons[0];

	for (float i = 0; i < menu_vadv_buttons.length; i++) {
		if (menu_vadv_buttons[i] == prev_id) {
			if (i + 1 >= menu_vadv_buttons.length)
				break;

			ret = menu_vadv_buttons[i + 1];
			break;
		}
	}

	return ret;
};

string(string next_id) Menu_VideoAdv_GetPreviousButton =
{
	if (next_id == "")
		return menu_vadv_buttons[menu_vadv_buttons.length - 1];

	string ret = menu_vadv_buttons[menu_vadv_buttons.length - 1];

	for (float i = menu_vadv_buttons.length - 1; i > 0; i--) {
		if (menu_vadv_buttons[i] == next_id) {
			if (i - 1 < 0)
				break;

			ret = menu_vadv_buttons[i - 1];
			break;
		}
	}

	return ret;
};

void() Menu_Video_Adv =
{
	if (!menu_vadv_init)
		Menu_VideoAdv_Init();

	Menu_DrawBackground();
	Menu_DrawTitle("ADVANCED VIDEO");

	Menu_DrawMapPanel();

	// Realtime lighting
	Menu_Button(1, "va_hiend", "HIGH-END LIGHTING", "Light the world in realtime with proper shadows. Costly.") ? Menu_VideoAdv_ToggleHighEnd() : 0;
	Menu_DrawOptionValue(1, current_va_hiend ? "ENABLED" : "DISABLED");

	// Render Scale -- renders below native and upscales. The single biggest
	// performance lever on a phone.
	Menu_Button(2, "va_scale", "RENDER SCALE", "Below 1 is faster; above 1 supersamples for a sharper image.") ? 0 : 0;
	Menu_CvarSlider(2, "va_scale", [0.5, 2, 15], "r_renderscale", false, false, false);

	// Anisotropic Filtering
	Menu_Button(3, "va_aniso", "ANISOTROPIC", "Sharpen textures viewed at an angle.") ? 0 : 0;
	Menu_CvarSlider(3, "va_aniso", [1, 16, 15], "gl_texture_anisotropic_filtering", true, false, false);

	// Dynamic Lights
	Menu_Button(4, "va_dynlt", "DYNAMIC LIGHTS", "Muzzle flashes and explosions light the world.") ? Menu_VideoAdv_ToggleDynamic() : 0;
	Menu_DrawOptionValue(4, current_va_dynlt ? "ENABLED" : "DISABLED");

	// Bloom
	Menu_Button(5, "va_bloom", "BLOOM", "Glow around bright areas.") ? Menu_VideoAdv_ToggleBloom() : 0;
	Menu_DrawOptionValue(5, current_va_bloom ? "ENABLED" : "DISABLED");

	// Fast Sky
	Menu_Button(6, "va_fsky", "FAST SKY", "Draw a flat sky instead of a skybox.") ? Menu_VideoAdv_ToggleFastSky() : 0;
	Menu_DrawOptionValue(6, current_va_fsky ? "ENABLED" : "DISABLED");

	// Viewmodel
	Menu_Button(7, "va_vmodel", "VIEW MODEL", "Show the weapon in first person.") ? Menu_VideoAdv_ToggleViewmodel() : 0;
	Menu_DrawOptionValue(7, current_va_vmodel ? "ENABLED" : "DISABLED");

	// View Bob
	Menu_Button(8, "va_bob", "VIEW BOB", "Bob the camera while walking.") ? Menu_VideoAdv_ToggleBob() : 0;
	Menu_DrawOptionValue(8, current_va_bob ? "ENABLED" : "DISABLED");

	// Brightness
	Menu_Button(9, "va_brite", "BRIGHTNESS", "Lift the whole image -- helps in daylight.") ? 0 : 0;
	Menu_CvarSlider(9, "va_brite", [0, 0.5, 10], "brightness", false, false, false);

	Menu_DrawDivider(10.25);
	Menu_Button(-1, "va_back", "BACK", "Return to Configuration Menu.") ? current_menu = MENU_OPTIONS : 0;

	sui_pop_frame();
};
