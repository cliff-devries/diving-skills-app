-- ============================================================
-- Migration v73 — seed the 12 Upstate Diving email templates
--                 that v66/v67 define but may not exist yet
--
-- Run once in the Supabase SQL editor.
-- Safe to re-run: every INSERT is guarded by WHERE NOT EXISTS.
-- The "Sign-up confirmation" template (seeded by v65) is NOT
-- touched here; only the 12 additional templates are added.
-- All templates are manual and OFF by default.
-- ============================================================

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$0 Lead Magnet Response$n$,
       $t$Thank you for downloading "Five Ways to Know if Your Child Is a Diver"$t$,
       $t$Hi {{parent_first_name}},

Thank you for downloading our guide, "Five Ways to Know if Your Child Is a Diver." We're thrilled that you're interested in learning more about springboard and platform diving and how it can benefit your child.

At Upstate Diving, we run diving lessons to help your child succeed. We build kids confidence, strength, and discipline through diving—whether they're just curious about the sport or ready to take their first leap off the board. Our programs are designed to support families like yours at every stage, from beginner classes to elite competitive training.

If you'd like, we'd be happy to answer your questions or bring you and your child in to come try out practice.

We're excited to help your child discover whether diving is the right fit—and to make their first experience safe, fun, and inspiring.

Warmly,
Cliff

P.S. Check out our Instagram: https://www.instagram.com/upstatediving/$t$,
       'manual', 0, FALSE, 110
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$0 Lead Magnet Response$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$1 Information - Registration (RIT)$n$,
       $t$Signing up for Upstate Diving$t$,
       $t$Hi {{parent_first_name}},

It's great to meet you! Here is the information on signing up for Upstate Diving. We run a trial for all of our new divers to make sure divers are able to swim in the deep end and we select the right diving class for them to start.

Follow the simple steps below to register {{diver_first_name}}.

1. Sign up your child with AAU Diving. Go to AAU Diving: [[LINK: AAU Diving]]. This is our required sports insurance.

A. You can register online here: [[LINK: AAU Sports Athlete Memberships]]
B. Purchase an annual membership (September 1 – August 31)
C. Select the club: Upstate NY Diving.

The AAU online system will instantly create a card with your AAU ID number.

2. Complete the Upstate Diving registration. Use your private link to enter {{diver_first_name}}'s AAU ID number and sign the photo release, accident waiver and release of liability (it takes about two minutes):
{{followup_link}}

3. After you have completed the AAU registration and the Upstate NY Diving registration, we will set up a time for {{diver_first_name}}'s trial class.

Thank you!
-Cliff

P.S. Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 120
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$1 Information - Registration (RIT)$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$2 Evaluation - Free Trial (RIT)$n$,
       $t${{diver_first_name}}'s free trial at Upstate Diving$t$,
       $t$Hi {{parent_first_name}}!

We are excited to have {{diver_first_name}} come in for a diving free trial. Please remember, divers need to be able to swim 20 yards in the deep end.

{{diver_first_name}}'s free trial is {{trial_date}} at [[trial time]].

Come to the RIT pool for your evaluation and please bring the following: Suit and towel for pool. Divers do not use goggles.

Pool Directions
Once entering campus at the main entrance (indicated with a VERY large sign: "Rochester Institute of Technology, Founded 1829"), follow the signs to the Gordon Fieldhouse and Activities Center. Park in Parking Lot D. RIT Campus Maps: [[LINK: RIT Campus Maps]]

Enter the Fieldhouse at the lower level doors.

Please give yourself a couple extra minutes to get into the pool area. The lifeguards will open up the pool doors at about [[pool doors open time]].

An Upstate Diving Parent Onboarding Specialist will greet you at [[greeting time]]. They will escort you to the pool.

Kathryn DeVinney
or
Lindsay Thaine

After entering the Fieldhouse the pool hallway will be on the right directly behind the front desk. Go to the end of the hallway, pass through the double doors and turn left. The pool deck will be through the silver stainless steel door.

Kathryn and/or Lindsay will be able to answer your questions as your diver tests with our Coaches. Our phones to text are Kathryn 585-739-9413, Lindsay 585-748-2947

If you have any other questions do not hesitate to call.
585-224-5130

-Cliff

P.S. Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 130
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$2 Evaluation - Free Trial (RIT)$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$3 Post-Evaluation - Sign Up (RIT)$n$,
       $t$Thank you for bringing {{diver_first_name}} in to Upstate Diving$t$,
       $t$Hi {{parent_first_name}},

Thank you for bringing {{diver_first_name}} in for the free evaluation at Upstate Diving. We hope {{diver_first_name}} had a great time. If you would like to sign up and continue diving, please send me an email and let me know which times work for you.

After you have confirmed your Learn to Dive class(es) you will receive an email invoice that you can pay online. We generally recommend divers start with two or three days a week.

Class Times
We have the following spots open for Learn to Dive:
RIT pool - Tuesdays from 6:45 - 7:30 PM
RIT pool - Thursdays from 6:45 - 7:30 PM
and
Diving Dryland - Saturdays from 10:45 - 11:30 AM

Dryland Directions
305 Commerce Dr., #6 is located Near Marketplace Mall just off of W. Henrietta Rd. As you drive down Commerce Drive the warehouse with the Dryland Facility will be on your left about 1 mile down the road. The facility has a sign on the door that says "Upstate Diving Dryland Facility"

Prices & Billing
If you decide to continue, you will receive an email invoice from Upstate Diving that you may pay online with a credit card. Each month, on the first of the month, you will receive an email invoice.

LTD Monthly Pricing:
1 practice per week: $80
2 practices per week: $120

Email List and GroupMe Messages
Make sure you have signed up for our email & GroupMe Messaging to receive weather-related facility closings and other essential updates.

Upstate Diving email sign-up form: https://zc.vg/0AP8k

Upstate Diving GroupMe: [[LINK: GroupMe]]

Thanks!

-Cliff

P.S. Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 140
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$3 Post-Evaluation - Sign Up (RIT)$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$4 Confirmation - Welcome$n$,
       $t$Welcome to Upstate Diving!$t$,
       $t$Welcome to Upstate Diving!

Thank you for signing up {{diver_first_name}} at Upstate Diving. We hope {{diver_first_name}} is excited to start diving!

We have added {{diver_first_name}} to the Learn to Dive roster, and {{diver_first_name}} is all set for the rest of [[month]]. You will receive an invoice soon for the remainder practices for the month. Beginning in [[next month]] you will receive an email invoice on the first of each month.

{{diver_first_name}} is registered for the following practice times:
[[practice times, for example: Tuesdays from 6:45 - 7:30 PM at the RIT Pool. Saturdays from 10:00 - 10:45 AM at Diving Dryland]]

If you miss a practice, we have make-up times available for you. Please just send me an email and I will let you know when the next open practice times are. (Sometimes a make-up time may not be available if we are full)

Also, if you have a friend that would like to start diving, add their first name, last name and their email. We have a referral program where you and your friend will receive a free month of diving if they sign up!

Email List and GroupMe Messages
Make sure you have signed up for our email & GroupMe Messaging to receive weather-related facility closings and other essential updates.

Upstate Diving email sign-up form: https://zc.vg/0AP8k

Upstate Diving GroupMe: [[LINK: GroupMe]]

-Cliff

P.S. Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 150
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$4 Confirmation - Welcome$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$5 Goals & Referral$n$,
       $t$Tell us your goals for {{diver_first_name}}$t$,
       $t$Hi {{parent_first_name}},

Thank you for joining Upstate Diving. We are thrilled to have you as part of the Upstate Diving Club. We hope {{diver_first_name}} is having a great time. We would like to know what your goals are so we can help your diver achieve those goals. Please take a minute to fill out the short survey and let us know what your goals are, how we could make registration easier for you and what we could do better.

Upstate Diving New Diver Survey: [[LINK: New Diver Survey]]

Also, if you have a friend that would like to start diving, add their first name, last name and their email. We have a referral program where you and your friend will each receive [[referral reward - the original text here was unclear: "$100 with of Upstate Diving instruction"]] if they sign up and stay for 1 month!

Upstate Diving Referral Form: [[LINK: Referral Form]]

Email List and GroupMe Messages
Make sure you have signed up for our email & GroupMe Messaging to receive weather-related facility closings and other essential updates.

Upstate Diving email sign-up form: https://zc.vg/0AP8k

Upstate Diving GroupMe: [[LINK: GroupMe]]

Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 160
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$5 Goals & Referral$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$1 Canandaigua - Information & Registration$n$,
       $t$Signing up for Upstate Diving - Canandaigua$t$,
       $t$Hi {{parent_first_name}},

Nice to meet you! Here is the information on signing up for Upstate Diving - Canandaigua.

Please complete {{diver_first_name}}'s registration by following the steps below. We run a trial for all of our new divers to make sure divers are able to swim in the deep end and we select the right diving class for them to start.

1. Sign up your child with AAU Diving. Go to AAU Diving: [[LINK: AAU Diving]]. This is our required sports insurance.

A. You can register online here: [[LINK: AAU Sports Athlete Memberships]]
B. Purchase an annual membership (September 1 – August 31)
C. Select the club: Upstate NY Diving.

The AAU online system will instantly create a card with your AAU ID number.

2. Complete the Upstate Diving registration. Use your private link to enter {{diver_first_name}}'s AAU ID number and sign the photo release, accident waiver and release of liability (it takes about two minutes):
{{followup_link}}

3. After you have completed the AAU registration and the Upstate NY Diving registration, we will set up a time for {{diver_first_name}}'s free evaluation.

If you have any other questions do not hesitate to call.
585-224-5130

Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 170
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$1 Canandaigua - Information & Registration$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$2 Canandaigua - Free Trial$n$,
       $t${{diver_first_name}}'s free trial at Upstate Diving - Canandaigua$t$,
       $t$Hi {{parent_first_name}},

Thank you for registering {{diver_first_name}} with Upstate Diving - Canandaigua. We are excited to have {{diver_first_name}} come in for a diving free trial. Please remember, divers need to be able to swim 20 yards in the deep end.

We have set up your free trial for {{trial_date}} at [[trial time]].

Come to the Canandaigua Academy Pool for your first practice and please bring the following: Suit and towel for pool. Divers do not use goggles.

Pool Directions
Once entering campus at the main entrance on East street, park in the south parking lot and enter in the Athletics Entrance. The pool entrance will be open your left. Canandaigua Academy High School Map: [[LINK: Canandaigua Academy High School Map]]

If you have any other questions do not hesitate to call.
585-224-5130

Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 180
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$2 Canandaigua - Free Trial$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$3 Canandaigua - Post-Evaluation Sign Up$n$,
       $t$Thank you for bringing {{diver_first_name}} in to Upstate Diving - Canandaigua$t$,
       $t$Hi {{parent_first_name}},

Thank you for bringing {{diver_first_name}} in for the free evaluation at Upstate Diving - Canandaigua. We hope {{diver_first_name}} had a great time. If you would like to sign up and continue diving, please send me an email and let me know which times work for you. After you have confirmed your Learn to Dive class(es) you will receive an email invoice that you can pay online. We generally recommend divers start with two days a week.

Class Times
We have the following spots open for Learn to Dive:
Canandaigua Academy pool - Wednesdays from 6:00 - 6:45 PM
and
Diving Dryland - Saturdays from 10:00 - 10:45 AM

Dryland Directions
305 Commerce Dr., #6 is located Near Marketplace Mall just off of W. Henrietta Rd. As you drive down Commerce Drive the warehouse with the Dryland Facility will be on your left about 1 mile down the road. The facility has a sign on the door that says "Upstate Diving Dryland Facility"

Prices & Billing
If you decide to continue, you will receive an email invoice from Upstate Diving that you may pay online with a credit card. Each month, on the first of the month, you will receive an email invoice.

LTD Monthly Pricing:
1 practice per week: $50
2 practices per week: $80

Email List and GroupMe Messages
Make sure you have signed up for our email & GroupMe Messaging to receive weather-related facility closings and other essential updates.

Upstate Diving email sign-up form: https://zc.vg/0AP8k

Upstate Diving GroupMe: [[LINK: GroupMe]]

If you have any other questions do not hesitate to call.
585-224-5130

Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 190
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$3 Canandaigua - Post-Evaluation Sign Up$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$0 Canandaigua - Wait List$n$,
       $t$You are on the Upstate Diving Canandaigua wait list$t$,
       $t$Hi {{parent_first_name}},

Thank you for signing up on the Upstate Diving Canandaigua wait list. Right now all of our spots are full. We will let you know as soon as there is an opening.
In the meantime, if you would like to check out the classes that we offer at RIT and our dryland diving facility, please email me at Cliff@upstatediving.com.
Thanks,
-Cliff

Stay connected with us on Instagram (https://www.instagram.com/upstatediving/) and Facebook (https://www.facebook.com/upstatenydiving) for the latest updates and news.$t$,
       'manual', 0, FALSE, 200
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$0 Canandaigua - Wait List$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$Canandaigua Start - Trial Directions$n$,
       $t${{diver_first_name}}'s free trial at Upstate Diving - Canandaigua$t$,
       $t$Hi {{parent_first_name}},

Thanks for signing up for a free trial at Upstate Diving! We have a spot for {{diver_first_name}} to come in [[trial day and time, for example: tonight from 6 PM to 6:45 PM]] at our Canandaigua Academy location.

Here are the directions for the free trial:

Come to the Canandaigua Academy Pool for your first practice and please bring the following:

Suit and towel for pool.
Divers do not wear goggles.

Pool Directions
Once entering campus at the main entrance on East street, park in the south parking lot and enter in the Athletics Entrance. The pool entrance will be open your left. Canandaigua Academy High School Map: [[LINK: Canandaigua Academy High School Map]]

Billing
Once you have completed your registration and you have been assigned a class, you will receive an email invoice from Upstate Diving. You may pay online with a credit card or an ACH bank transfer. Each month, on the first of each month, you will receive an email invoice.

Communication
Make sure you have signed up for our email updates
Upstate Diving email sign-up form: https://zc.vg/0AP8k

GroupMe Communications
Please sign up for GroupMe to receive instant updates on weather-related facility closings or emergency changes. If you are not on the GroupMe list you will need to wait for the email update for weather related closings or other important information. (and it may be too late…)

Upstate Diving GroupMe: [[LINK: GroupMe Canandaigua]]$t$,
       'manual', 0, FALSE, 210
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$Canandaigua Start - Trial Directions$n$);

INSERT INTO public.crm_email_templates (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT $n$Canandaigua Start - Continue After Trial$n$,
       $t$Continuing at Upstate Diving - Canandaigua$t$,
       $t$Hi {{parent_first_name}},

Looks like you got the registration all worked out. I hope {{diver_first_name}} enjoyed the first practice! If you would like to continue, here is the information to start at Canandaigua! If you would like to start, please send me an email and I will add {{diver_first_name}} to the practice roster.

Canandaigua Practice Times
Wednesdays 6 PM to 7:30 PM

Price
$70 per month

Pool Directions
Once entering campus at the main entrance on East street, park in the south parking lot and enter in the Athletics Entrance. The pool entrance will be open your left. Canandaigua Academy High School Map: [[LINK: Canandaigua Academy High School Map]]

Billing
Once you have completed your registration and you have been assigned a class, you will receive an email invoice from Upstate Diving. You may pay online with a credit card or an ACH bank transfer. Each month, on the first of each month, you will receive an email invoice.

Communication
Make sure you have signed up for our email updates
Upstate Diving email sign-up form: https://zc.vg/0AP8k

GroupMe Communications
Please sign up for GroupMe to receive instant updates on weather-related facility closings or emergency changes. If you are not on the GroupMe list you will need to wait for the email update for weather related closings or other important information. (and it may be too late…)

GroupMe Canandaigua: [[LINK: GroupMe Canandaigua]]$t$,
       'manual', 0, FALSE, 220
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = $n$Canandaigua Start - Continue After Trial$n$);
