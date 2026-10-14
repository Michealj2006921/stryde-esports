# STRYDE backend foundation

This repository is being developed in stages. The current website is a static frontend; this folder starts the database/backend foundation.

## Stack
- Supabase Auth + PostgreSQL for accounts and persistent platform data.
- Supabase Row Level Security (RLS) for database access control.
- Vercel for deployment and server-side API functions when those are added.

## Initial schema
Apply `supabase/migrations/0001_initial_schema.sql` to a **new Supabase project** using the Supabase Dashboard → SQL Editor. Review the SQL before running it. This creates:
- Profiles linked to Supabase Auth users
- Squads and squad memberships
- Tournaments
- Tournament registrations
- Matches, match participants, and published results
- Initial indexes, auth profile trigger, and RLS policies

## Important setup sequence
1. Create a Supabase project.
2. Open SQL Editor and run the migration file.
3. Create a test account through Supabase Auth or the app once authentication UI is connected.
4. Promote the first admin manually from the SQL Editor only after that account has a profile:
   `update public.profiles set role = 'admin' where username = 'YOUR_USERNAME';`
5. Keep the Supabase service-role/secret key server-side. Never commit it or place it in browser JavaScript.
6. Use the publishable key in browser code only after checking the RLS policies and grants.

## Current limitations
- The migration has not been run against a live Supabase project yet.
- No live database credentials have been configured.
- Authentication UI, API routes, and frontend data integration are not connected yet.
- Tournament records and match statistics shown in the existing frontend remain sample presentation content until replaced with database-backed records.
- Payment processing, prize payouts, automated match verification, and anti-cheat systems are out of scope for this first backend milestone.

## Next implementation milestone
Connect Supabase Auth to the existing frontend, then implement tested tournament listing and registration flows. Add Vercel server-side functions only where trusted server logic is needed.
