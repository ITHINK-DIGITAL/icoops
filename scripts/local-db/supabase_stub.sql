-- Minimal stand-in for the parts of Supabase that the migrations rely on, so that migrations
-- and database tests can run on a plain Postgres 16 where Docker is unavailable.
-- LOCAL USE ONLY. CI and every real environment use the actual Supabase stack, never this file.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap with schema extensions;

create schema auth;
create table auth.users (
  id uuid primary key,
  instance_id uuid,
  aud text,
  role text,
  email text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  -- Token columns have no default here on purpose: GoTrue needs them non-null, so a seed that
  -- forgets one must fail locally instead of only against the real stack.
  confirmation_token text not null,
  recovery_token text not null,
  email_change_token_new text not null,
  email_change text not null,
  email_change_token_current text not null,
  phone_change text not null,
  phone_change_token text not null,
  reauthentication_token text not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table auth.identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  provider_id text not null,
  provider text not null,
  identity_data jsonb not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create function auth.uid() returns uuid language sql stable as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
    ), ''
  )::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;
create function auth.role() returns text language sql stable as $$
  select coalesce(auth.jwt() ->> 'role', '')
$$;

grant usage on schema public, extensions to anon, authenticated, service_role;
grant usage on schema auth to service_role;
-- Supabase grants everything on new public objects to the API roles by default; mirror that so
-- that the migrations' explicit revokes are what is actually being tested.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
