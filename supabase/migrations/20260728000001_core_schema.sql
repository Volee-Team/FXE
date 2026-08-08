-- FXE Tennis v1: core schema.
--
-- Design notes that are easy to get wrong later:
--
--  * Player-centred. Clinics repeat and disappear; players remain for years.
--    `players` is the long-lived entity, `accounts` is just the login.
--  * Children store date_of_birth, NOT age. A stored age is silently wrong
--    within a year. Age is derived on read.
--  * Everything archives. Nothing is deleted: players deactivate, clinics and
--    registrations cancel, templates and news archive.
--  * Court assignment is a column on registrations, not its own table. The
--    guide describes it as (clinic, player, court), which is exactly the row
--    that already joins clinic and player.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- enums ----

create type account_type       as enum ('adult', 'parent', 'both');
create type account_role       as enum ('member', 'admin');
create type player_kind        as enum ('adult', 'junior');
create type clinic_audience    as enum ('ladies', 'men', 'coed', 'juniors');
create type clinic_status      as enum ('draft', 'published', 'canceled');
create type registration_status as enum ('in', 'pool', 'response_needed', 'canceled');
create type message_audience   as enum ('everyone', 'in', 'pool', 'response_needed', 'unpaid');
create type news_audience      as enum ('adults', 'juniors', 'everyone');
create type news_status        as enum ('draft', 'published');
create type registration_source as enum ('self', 'admin');

-- --------------------------------------------------------------- tables ----

create table public.accounts (
  id            uuid primary key references auth.users (id) on delete cascade,
  first_name    text not null,
  last_name     text not null,
  email         text not null,
  phone         text,
  account_type  account_type not null default 'adult',
  role          account_role not null default 'member',
  push_enabled  boolean not null default false,
  created_at    timestamptz not null default now()
);

-- One row per person who can be registered for a clinic. An adult account has
-- one (themselves); a parent account has one per child, plus their own if they
-- also play. account_id is the owner/guardian, never the player themselves for
-- juniors.
create table public.players (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references public.accounts (id) on delete cascade,
  kind          player_kind not null,
  first_name    text not null,
  last_name     text not null,
  date_of_birth date,          -- juniors: required. adults: optional.
  adult_rating  text,          -- adults only. Value list pending Tara.
  is_member     boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),

  constraint junior_has_dob check (kind <> 'junior' or date_of_birth is not null)
);

create index players_account_idx on public.players (account_id);
create index players_name_idx    on public.players (lower(last_name), lower(first_name));
create index players_active_idx  on public.players (is_active) where is_active;

-- Private coaching notes live in their own table so a careless `select *` on
-- players can never leak them, and so the grant is a single obvious line.
create table public.player_notes (
  player_id  uuid primary key references public.players (id) on delete cascade,
  body       text not null default '',
  updated_at timestamptz not null default now()
);

create table public.clinic_templates (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null,
  audience             clinic_audience not null,
  category             text,
  description          text,
  price_cents          integer not null default 0,
  default_start_time   time not null default '09:00',
  duration_minutes     integer not null default 60,
  internal_capacity    integer not null default 8,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),

  constraint template_capacity_positive check (internal_capacity > 0)
);

create table public.clinics (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid references public.clinic_templates (id) on delete set null,
  name              text not null,
  audience          clinic_audience not null,
  category          text,
  description       text,
  price_cents       integer not null default 0,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  member_opens_at   timestamptz not null,
  public_opens_at   timestamptz not null,
  closes_at         timestamptz,
  internal_capacity integer not null,
  status            clinic_status not null default 'draft',
  canceled_at       timestamptz,
  created_at        timestamptz not null default now(),

  constraint clinic_ends_after_start   check (ends_at > starts_at),
  constraint clinic_public_after_member check (public_opens_at >= member_opens_at),
  constraint clinic_capacity_positive  check (internal_capacity > 0)
);

create index clinics_starts_idx on public.clinics (starts_at);
create index clinics_status_idx on public.clinics (status, starts_at);

create table public.registrations (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references public.clinics (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete cascade,
  status        registration_status not null,
  paid          boolean not null default false,
  court_number  smallint,                       -- admin-only, 1..5
  source        registration_source not null default 'self',
  registered_at timestamptz not null default now(),
  invited_at    timestamptz,
  responded_at  timestamptz,
  canceled_at   timestamptz,
  canceled_by   uuid references public.accounts (id) on delete set null,

  constraint court_in_range check (court_number is null or court_number between 1 and 5)
);

-- A player may hold at most ONE live registration per clinic. Canceled rows are
-- excluded so a player who cancels can register again, and history survives.
-- This is also what makes register_for_clinic idempotent under retry.
create unique index registrations_one_live
  on public.registrations (clinic_id, player_id)
  where status in ('in', 'pool', 'response_needed');

create index registrations_clinic_status_idx on public.registrations (clinic_id, status);
create index registrations_player_idx        on public.registrations (player_id);

create table public.clinic_messages (
  id        uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics (id) on delete cascade,
  body      text not null,
  audience  message_audience not null,
  sent_at   timestamptz not null default now()
);

create index clinic_messages_clinic_idx on public.clinic_messages (clinic_id, sent_at desc);

-- Recipients are snapshotted at send time for TARGETED messages. This resolves
-- the guide's contradiction between "every message stays on Clinic Details" and
-- "messages can be sent to one group": an 'everyone' message is visible to
-- anyone registered for the clinic (including people who join later), and a
-- targeted message stays visible only to the people it was sent to.
create table public.clinic_message_recipients (
  message_id uuid not null references public.clinic_messages (id) on delete cascade,
  player_id  uuid not null references public.players (id) on delete cascade,
  primary key (message_id, player_id)
);

create table public.news_posts (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null,
  audience     news_audience not null,
  status       news_status not null default 'draft',
  published_at timestamptz,
  archived_at  timestamptz,
  created_at   timestamptz not null default now()
);

-- Unread state is per ACCOUNT, not per player: a parent managing three kids
-- reads an announcement once.
create table public.news_reads (
  news_id    uuid not null references public.news_posts (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  read_at    timestamptz not null default now(),
  primary key (news_id, account_id)
);

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references public.accounts (id) on delete cascade,
  type        text not null,
  entity_type text,
  entity_id   uuid,
  body        text not null,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);

create index notifications_account_idx on public.notifications (account_id, created_at desc);

create table public.devices (
  account_id uuid not null references public.accounts (id) on delete cascade,
  apns_token text not null,
  platform   text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (account_id, apns_token)
);
