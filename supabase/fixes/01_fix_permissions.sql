-- =====================================================================
-- AZIZA Boutique — Part 1: Diagnose and fix schema public permissions
-- Run each section on its own, in order, in the Supabase SQL Editor.
-- No DO blocks and no transactions; every statement stands alone.
-- =====================================================================


-- ---------------------------------------------------------------------
-- A) The most important check: which role is the editor running as?
-- ---------------------------------------------------------------------
-- Note: the SQL Editor has a Role selector in the bottom right of the editing area.
-- It must be set to "postgres". If it is anon or authenticated, CREATE TABLE fails with
-- exactly: 42501 permission denied for schema public.

reset role;

select current_user, session_user;
-- Expected: postgres | postgres
-- If current_user is not postgres: change the Role selector to postgres, then run this section again.


-- ---------------------------------------------------------------------
-- B) Diagnosis: who owns the schema, and what permissions do the roles have?
-- ---------------------------------------------------------------------
select n.nspname                      as schema,
       pg_get_userbyid(n.nspowner)    as schema_owner,
       pg_get_userbyid(d.datdba)      as database_owner,
       n.nspacl                       as acl
  from pg_namespace n, pg_database d
 where n.nspname = 'public' and d.datname = current_database();
-- Normal in Supabase: schema_owner = pg_database_owner (or postgres), database_owner = postgres

select r                                         as role,
       has_schema_privilege(r, 'public', 'usage')  as has_usage,
       has_schema_privilege(r, 'public', 'create') as has_create
  from unnest(array['postgres', 'anon', 'authenticated', 'service_role']) as r;
-- Required: postgres = true/true, and the other three usage = true (create not needed)


-- ---------------------------------------------------------------------
-- C) Fix: restore Supabase's default permissions on schema public
--    (needed only if B showed false somewhere)
-- ---------------------------------------------------------------------
grant usage, create on schema public to postgres;
grant usage on schema public to anon, authenticated, service_role;

grant all on all tables    in schema public to postgres, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;
grant all on all routines  in schema public to postgres, service_role;

-- Supabase's default for API roles. The real protection is RLS (enabled on every table),
-- and Part 2 re-tightens admins and orders after this.
grant select, insert, update, delete on all tables in schema public to anon, authenticated;

-- If the first statement in this section fails with 42501 too:
-- the postgres role is no longer the schema owner or a member of the owner,
-- and nothing can fix that from inside the project. Send the output of section B
-- to Supabase Support (Dashboard → Support).


-- ---------------------------------------------------------------------
-- D) Re-check: everything must now be true
-- ---------------------------------------------------------------------
select r                                         as role,
       has_schema_privilege(r, 'public', 'usage')  as has_usage,
       has_schema_privilege(r, 'public', 'create') as has_create
  from unnest(array['postgres', 'anon', 'authenticated', 'service_role']) as r;
