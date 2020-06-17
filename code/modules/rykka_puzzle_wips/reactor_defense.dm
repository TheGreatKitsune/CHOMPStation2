//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*	I have precisely 0 knowledge of what inspired me to make horrifically "pretty" code-comment blocks but fuck it here's Rykka's masterpiece.				//
 *	TL;DR - This is the Reactor Defense Code, based off of GTFO's Reactor Defense and Warframe's Defense style missions. Keep the objective alive,			//
 *	preferably undamaged through a number of waves, and you're able to progress. Mechanical challenges are more fun than "shoot thing, win". More to come.	//
 *////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*												Object Definition, Initialize, Process															*/
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

GLOBAL_LIST_INIT(reactor_mob_spawners, list()) // Define our global list here. This is used for the spawners.

// List of tabs used for NanoUI Displays. If you're not sure how defines work, refer to the .dm reference docs.
#define IDLE 1
#define WARMUP 2
#define ENGAGED 3
#define FINISHED 4

/obj/structure/damaged_reactor // Damaged Reactor object used as the "thing" we interact with
	name = "damaged reactor"
	desc = "You shouldn't be able to read this! OOC: Poke @Rykka Stormheart or ask in dev, the reactors should be a subtype of damaged_reactor!"
	icon = 'icons/obj/damaged_reactor.dmi'
	icon_state = "reactor_off"
	density = 1
	anchored = TRUE
	climbable = FALSE
	breakable = FALSE
	var/icon_state_warmup = null					// Icon to use when the reactor is engaged/warming up
	var/icon_state_severe_damage = null				// Icon to use when the reactor has taken severe damage.
	var/icon_state_powered = null					// Icon to use once the reactor is at full power
	var/active_defense = 0							// Are we actively in "defense" mode? (IE has someone engaged the defense gamemode?)
	var/health = 2000								// The Reactor's health value
	var/maxhealth = 2000							// The maximum health this object can have.
	var/list/spawners = list()						// The list of wave spawners we have (Defined at init.)
	var/reactor_id = null							// Our ID, used to link the reactor + the spawners specific to it, as well as the control console.
	
	// Customization Options. Use these to customize how you want the mode to play out.
	var/current_wave = 1							// The wave we're on currently. (Needed if # of waves is > 1)
	var/waves = 1									// Total amount of waves we'll have. TODO - figure out a method of spawning all at once on wave start vs continuous spawns.
	var/warmup = TRUE								// Does the reactor require a "warmup"/prep time before the waves start?
	var/warmup_time = 30 SECONDS					// How long is our warmup period?
	var/warmup_complete = world.time + warmup_time 	// When is our warmup complete?
	var/wave_length = 90 SECONDS					// How long are our waves?
	var/wave_complete = world.time + wave_length	// When is the wave complete?
	var/state = IDLE								// What state are we in currently? (This is used for tracking the spawns and such)
	var/area_defense = FALSE						// Are we using area defense as well as object defense? (IE, you must stay inside /area/ during the waves.)
	
	// Nano UI Variables, don't fuck with these unless you know what you're changing.
	var/current_tab = IDLE
	
	/* 	== Spawning Variables. == */
	// Change these on the subtype of the reactor, for custom mob lists.
	// Weighted with values (not %chance, but relative weight)
	// Can be left value-less for all equally likely
	var/list/mobs_to_pick = list()
	
	// Settings to help mappers/coders have their mobs do what they want in this case
	var/faction				// To prevent infighting if it spawns various mobs, set a faction
	var/atmos_comp = FALSE	// TRUE will set all their survivability to be within 20% of the current air
	
	// Internal Use Only
	var/mob/living/simple_mob/my_mob
	
/obj/structure/damaged_reactor/Initialize()
	. = ..()
	
	if(GLOB.reactor_mob_spawners[reactor_id]) // Does the list exist? Great, then we set the spawners var = to that list.
		spawners = GLOB.reactor_mob_spawners[reactor_id]
	else // Otherwise, we CRASH (create a runtime) so that debugging is aware there is a problem.
		CRASH("Reactor [reactor_id] at [x],[y],[z] ([get_area(src)]) couldn't find any spawners!")
		
	if(!LAZYLEN(mobs_to_pick)) // We CRASH (create a runtime) so that debugging is aware there is a problem. An empty list means nothing will happen when time comes for waves.
		CRASH("Reactor [reactor_id] at [x],[y],[z] ([get_area(src)]) had no mobs_to_pick set on it!")
			
	START_PROCESSING(SSobj, src)
	
/obj/structure/damaged_reactor/process() // This runs every 2 seconds/MC tick of the SSobj subsystem. I think.
	// Commenting out in favor of states. Leaving this just-in-case.
	// if(!active_defense) // Don't do anything unless we're actively in defense mode.
	//	return
	
	if(state == WARMUP)
		if(world.time >= warmup_complete)
			state = ENGAGED
			return
		warmup()
	
	else if(state == ENGAGED)
		defense_mode()
		
	/* Commenting out the my_mob stuff until I get a better handle on if it's needed or not.
	if(my_mob && my_mob.stat != DEAD) // Is our spawned mob alive still?
		return // No need to spawn
	*/
	
	if(faction) // Is there a faction var set? Set the spawned mobs faction to this.
		my_mob.faction = faction
	
	if(atmos_comp) // Are we actively setting the atmos survivability? Do so now.
		var/turf/T = get_turf(src)
		var/datum/gas_mixture/env = T.return_air()
		if(env)
			my_mob.minbodytemp = env.temperature * 0.8
			my_mob.maxbodytemp = env.temperature * 1.2

			var/list/gaslist = env.gas
			my_mob.min_oxy = gaslist["oxygen"] * 0.8
			my_mob.min_tox = gaslist["phoron"] * 0.8
			my_mob.min_n2 = gaslist["nitrogen"] * 0.8
			my_mob.min_co2 = gaslist["carbon_dioxide"] * 0.8
			my_mob.max_oxy = gaslist["oxygen"] * 1.2
			my_mob.max_tox = gaslist["phoron"] * 1.2
			my_mob.max_n2 = gaslist["nitrogen"] * 1.2
			my_mob.max_co2 = gaslist["carbon_dioxide"] * 1.2
	

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*													End Object Definition																		*/
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*	//		=====							Interaction Code Begins															=====		//
 *	//		=====			Handle Examine, attempting to interact with object, other "generic" code here.					=====		//
 *////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/obj/structure/damaged_reactor/attack_hand(var/mob/living/user) // Is a LIVING mob clicking on us? Sorry ghosts. :p
	if(!isliving(user)) // You're not alive. Stop. Bad.
		return // No clicky.
	switch(user.a_intent)
		if(I_HELP)
			ui_interact(user) // Open NanoUI
		if(I_HURT)
			var/mob/living/carbon/human/H = usr
			if(H.species.can_shred(H)) // This is a hard vore proc. Whyyyyy???
				attack_generic(H,10) // Handle doing damage here too, since it counts as an interaction.
				return
			// else if(H.species.) TODO: Figure out how to handle SHARP claws/etc for a very little bit of damage.
			else // You can't damage it without a tool!
				playsound(src, 'sound/effects/grillehit.ogg', 50, 1)
				user.do_attack_animation(src)
				user.visible_message("<span class = 'danger'>\The [user] slams their hand against \the [src], not appearing to damage it!</span>",
									"<span class = 'danger'>You don't appear to do anything to the heavy exterior of \the [src]!</span>")
		if(I_GRAB)
			to_chat(user, "<span class ='notice'>You can't grab a reactor! To open the menu, use help intent!</span>")
			return
		if(I_DISARM)
			to_chat(user, "<span class ='notice'>You can't disarm a reactor! To open the menu, use help intent!</span>")
			return

/obj/structure/damaged_reactor/examine(mob/user) // Are they inspecting the reactor?
	. = ..()

	if(health >= maxhealth) // Use >= in case someone varedits health higher than the "max".
		. += "<span class='notice'>It looks fully intact.</span>"
	else
		var/perc = health / maxhealth
		if(perc > 0.75)
			. += "<span class='notice'>It appears to have slight damage on the exterior, but nothing serious.</span>"
		else if(perc > 0.5)
			. += "<span class='warning'>It appears to be slightly misaligned, and the motor is humming louder than expected.</span>"
		else if(perc > 0.25)
			. += "<span class='warning'>It appears to be having trouble running, the rotations appearing dangerously slower than expected!</span>"
		else
			. += "<span class='danger'>It appears to be on the verge of shutdown, as the turbine oscillates wildly!</span>"

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*			=====							Interaction Code Ends															=====		*/
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


//////////////////////////////////////////////////////////////////////
//		=====		NanoUI Menu Stuff Begins Here		=====		//
//////////////////////////////////////////////////////////////////////

/obj/structure/damaged_reactor/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, force_open = 1)
	// End Header
	
	if(!user) // For some reason the user is null?
		return
	
	// We'll make data a list of options, to make it easier to add things later.
	var/list/data = get_ui_data()

	// Footer
	// Update the UI if it exists, returns null if no ui is passed/found
	ui = SSnanoui.try_update_ui(user, src, ui_key, ui, data, force_open)
	if(!ui) // The UI does not exist, so we'll create a new() one. For a list of parameters and their descriptions see the code docs in nano\README.md
		ui = new(user, src, ui_key, "damaged_reactor.tmpl", "Reactor Interface v2.52", 600, 600)
		ui.set_initial_data(data) // When the UI is first opened this is the data it will use
		ui.open() // Open the new UI window
		ui.set_auto_update(1) // Auto-update every Master Controller tick (every 2 seconds)

/* IF you're making a subtype and want to ADD data to this list, to add more things to NanoUI and such, do:
 *	/obj/structure/damaged_reactor/SUBTYPE/get_ui_data()
 *		var/list/data = ..() 
 *		data['thing'] = "Nope like this" 
 *		return data 
 *	This allows you to add more data to the get_ui_data proc or change the information in certain fields without overriding the main data list.
 */ 

/obj/structure/damaged_reactor/proc/get_ui_data()
	data["health"] = health
	data["wave"] = current_wave
	data["warmup_enabled"] = warmup
	data["currentTab"] = current_tab
	data["warmup_time_left"] = (warmup_complete - world.time) / 10 // We want to take the TOTAL time and subtract the CURRENT time, then divide it, to get our fancy UI percentage/time.

/obj/structure/damaged_reactor/Topic(href, href_list)
	if(..())
		return 1
		
	if(href_list["Engage Reactor"])
		if(!warmup) // If we do not have warmup set to TRUE, then we go right to starting the waves.
			current_tab = ENGAGED
			state = ENGAGED
			to_world("<span class='danger'><big>DEBUG: DEFENSE MODE ENGAGED.</big></span>")
		else
			current_tab = WARMUP
			state = WARMUP
			to_world("<span class='danger'><big>DEBUG: WARMUP STARTED.</big></span>")
		

//////////////////////////////////////////////////////////////////
/*		=====		NanoUI Menu Stuff Ends Here		=====		*/
//////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*	//		=====									-----Damage Handling Code-----																=====		//
 *	//		=====		We have to handle damage and health ourselves instead of relying on a parent to do so. 									=====		//
 *	//		=====		The following code handles health, taking damage, mobs inflicting damage, and any other damage-related scenarios. 		=====		//
 *////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/obj/structure/damaged_reactor/take_damage(var/damage = 0, var/sound_effect = 1)
	var/initialhealth = health // ...do we even need the initialhealth check?
	
	if(active_defense == 0) // Are we actively in a "defense" mode? If no, skip taking damage.
		return
	
	health = max(0, health - damage)
	
	if(health <= 0)
		failure_state() // You let it take too much damage!
	else
		if(sound_effect)
			playsound(src, 'sound/effects/grillehit.ogg', 100, 1) // Sound placeholder until I get something better
		if(health < maxhealth * 0.25 && initialhealth >= maxhealth * 0.25) // 25% or below
			visible_message("<span class='danger'><big>\The [src] groans under the strain, the motor thrumming in an off-pitch tone as safety parameters threaten to shut it down and the turbine oscillates inside!</big></span>")
			update_icon()
		else if(health < maxhealth * 0.5 && initialhealth >= maxhealth * 0.5) // 50% or below
			visible_message("<span class='danger'>\The [src] whines dangerously as the turbine struggles to maintain RPMs with the sustained damage!</span>")
			update_icon()
		else if(health < maxhealth * 0.75 && initialhealth >= maxhealth * 0.75) // 75% or below
			visible_message("<span class='notice'>\The [src] begins to shift out of alignment as the motor works harder to maintain speed!</span>")
			update_icon()
	return

/obj/structure/damaged_reactor/bullet_act(var/obj/item/projectile/Proj) // A bullet hit us

	var/proj_damage = Proj.get_structure_damage()
	if(!proj_damage)
		return

	..()
	take_damage(proj_damage) // Take damage according to the bullet's damage value.
	return

/obj/structure/damaged_reactor/blob_act() // In the unlikely event a blob is attacking the reactor, deal a flat 50 damage to it.
	take_damage(50)
	
/obj/structure/damaged_reactor/hitby(AM as mob|obj) // I forget precisely what the fuck this is for but w/e.
	..()
	visible_message("<span class='danger'>\The [src] was hit by [AM].</span>")
	var/tforce = 0
	if(ismob(AM))
		tforce = 40
	else if(isobj(AM))
		var/obj/item/I = AM
		tforce = I.throwforce
	take_damage(tforce)

/obj/structure/damaged_reactor/attack_generic(var/mob/user, var/damage) // Are simplemobs trying to attack the reactor?
	user.setClickCooldown(user.get_attack_speed()) // Control how fast they can attack/click
	
	if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD) // Is the damage over the minimum required threshold? Deal damage.
		visible_message("<span class='danger'>[user] tries to slice into \the [src] and does a little damage to the casing!</span>")
		take_damage(damage)
	else // Otherwise, they do nothing!
		visible_message("<span class='notice'>\The [user] doesn't appear to do anything to \the [src]!</span>")
	user.do_attack_animation(src)
	return 1

/obj/structure/damaged_reactor/attackby(obj/item/W as obj, mob/user as mob) // Object Interactions and more typecasting!
	if(!istype(W)) // This handles an edge case scenario.
		return

	// Slamming the reactor with something/someone.
	if(istype(W, /obj/item/weapon/grab) && get_dist(src,user)<2)
		var/obj/item/weapon/grab/G = W
		if(istype(G.affecting,/mob/living))
			var/mob/living/M = G.affecting
			var/state = G.state
			qdel(W)	// gotta delete it here because if reactor breaks, it won't get deleted - not sure if this is needed since the reactor *can't* break.
			switch (state)
				if(1)
					M.visible_message("<span class='warning'>[user] slams [M] against \the [src]!</span>")
					M.apply_damage(7)
					hit(10)
				if(2)
					M.visible_message("<span class='danger'>[user] bashes [M] against \the [src]!</span>")
					if (prob(50))
						M.Weaken(1)
					M.apply_damage(10)
					hit(25)
				if(3)
					M.visible_message("<span class='danger'><big>[user] crushes [M] against \the [src]!</big></span>")
					M.Weaken(5)
					M.apply_damage(20)
					hit(50)
			return
	
	if(W.flags & NOBLUDGEON) // Is this an item incapable of producing an x hit y message (typically for weapons that can't attack)?
		return
	
	if(!W.force || W.force <= 0) // If for some reason it's null, not a number, or less than 0/negative, we don't handle damage from it.
		return
	
	else // A grab isn't the thing hitting us! Therefore, we receive damage based on the tool striking us!
		user.setClickCooldown(user.get_attack_speed(W))
		if(W.damtype == BRUTE || W.damtype == BURN)
			user.do_attack_animation(src)
			hit(W.force)
		else
			playsound(src, 'sound/effects/grillehit.ogg', 75, 1)
		..()
	return

/obj/structure/damaged_reactor/proc/hit(var/damage, var/sound_effect = 1) // ...this is a silly way to do it but okay :p
	take_damage(damage)
	return

//////////////////////////////////////////////////////////////////
/*			=====		End Damage Code			=====			*/
//////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////
/*	//		=====		State Handling Code		=====			//
 *	//			Handle success and failure states here.			//
 *////////////////////////////////////////////////////////////////

/obj/structure/damaged_reactor/proc/failure_state() // Did the reactor take too much damage? Did the users leave the area? Trigger this and you "fail" the mode
	health = maxhealth // Reset our health to maximum
	active_defense = 0 // We're no longer actively defending, because we failed.
	
/obj/structure/damaged_reactor/proc/success_state() // Did we win? Is it finally over?
	active_defense = 0 // We're no longer actively defending, because we won.

//////////////////////////////////////////////////////////////
/*		=====		End State Handling Code		=====		*/
//////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////
/*		=====		Defense Mode, Warmup Code		=====	//
 *			We'll handle engaging defense mode here.		//
 *////////////////////////////////////////////////////////////

/obj/structure/damaged_reactor/proc/defense_mode()
	active_defense = 1
	
	if(waves > 1)
		

/obj/structure/damaged_reactor/proc/warmup()
	

//////////////////////////////////////////////////////////////
/*		=====		End Defense Mode, Warmup Code	=====	*/
//////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////
/*		=====			Spawner Code			=====		//
 *		We'll handle mob spawning, spawners, etc here.		//
 *////////////////////////////////////////////////////////////

/obj/effect/spawner/wave_spawner/
	name = "Wave Spawner"
	desc = "This is the location of our wave spawns!"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	invisibility = 101
	mouse_opacity = 0
	density = 0
	anchored = 1
	
	// Our Reactor ID - used in linking the parts together.
	var/reactor_id = null
	
/obj/effect/spawner/wave_spawner/Initialize() // When our object is loaded for the first time.
	. = ..()
	
	if(GLOB.reactor_mob_spawners[reactor_id]) // If our list already exists, just add ourselves to it.
		GLOB.reactor_mob_spawners[reactor_id] += src
	else
		GLOB.reactor_mob_spawners[reactor_id] = list(src) // No list yet for this reactor? Cool, we're starting one.



//////////////////////////////////////////////////////////////
/*		=====		End Spawner Code			=====		*/
//////////////////////////////////////////////////////////////

// We're done using these, undefine them.
#undef IDLE
#undef WARMUP
#undef ENGAGED
#undef FINISHED