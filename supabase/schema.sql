-- Run once in the Supabase SQL Editor. Game data is only accessible through validated RPCs.
create extension if not exists pgcrypto;
create table if not exists public.connect4_games (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_token_hash text not null,
  guest_token_hash text,
  board jsonb not null default '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]'::jsonb,
  turn int not null default 1,
  winner int not null default 0,
  status text not null default 'waiting',
  version int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_status check (status in ('waiting','playing','finished'))
);
alter table public.connect4_games enable row level security;
revoke all on public.connect4_games from anon, authenticated, public;

create or replace function public.c4_authorized(g public.connect4_games, secret text)
returns boolean language sql stable set search_path = '' as $$
 select secret is not null and length(secret) >= 32 and
 (g.host_token_hash = encode(extensions.digest(secret,'sha256'),'hex') or
  g.guest_token_hash = encode(extensions.digest(secret,'sha256'),'hex'));
$$;

create or replace function public.c4_view(g public.connect4_games, secret text)
returns jsonb language sql stable set search_path = '' as $$
 select jsonb_build_object('code',g.code,'board',g.board,'turn',g.turn,'winner',g.winner,
 'status',g.status,'version',g.version,'role',case when g.host_token_hash = encode(extensions.digest(secret,'sha256'),'hex') then 1 else 2 end);
$$;

create or replace function public.c4_create(secret text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare g public.connect4_games; new_code text;
begin
 if secret is null or length(secret) < 32 or length(secret) > 256 then raise exception 'Invalid player key'; end if;
 for i in 1..8 loop
  new_code := upper(substr(encode(extensions.gen_random_bytes(5),'hex'),1,8));
  begin
   insert into public.connect4_games(code,host_token_hash)
   values(new_code,encode(extensions.digest(secret,'sha256'),'hex')) returning * into g;
   return public.c4_view(g,secret);
  exception when unique_violation then null;
  end;
 end loop;
 raise exception 'Could not create room';
end; $$;

create or replace function public.c4_join(room text, secret text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare g public.connect4_games;
begin
 if secret is null or length(secret) < 32 or length(secret) > 256 then raise exception 'Invalid player key'; end if;
 select * into g from public.connect4_games where code=upper(trim(room)) for update;
 if not found then raise exception 'Room not found'; end if;
 if public.c4_authorized(g,secret) then return public.c4_view(g,secret); end if;
 if g.guest_token_hash is not null then raise exception 'Room is full'; end if;
 update public.connect4_games set guest_token_hash=encode(extensions.digest(secret,'sha256'),'hex'),
 status='playing',version=version+1,updated_at=now() where id=g.id returning * into g;
 return public.c4_view(g,secret);
end; $$;

create or replace function public.c4_get(room text, secret text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare g public.connect4_games;
begin
 select * into g from public.connect4_games where code=upper(trim(room));
 if not found or not public.c4_authorized(g,secret) then raise exception 'Room unavailable or access denied'; end if;
 return public.c4_view(g,secret);
end; $$;

create or replace function public.c4_move(room text, secret text, col int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare g public.connect4_games; player int; b int[]; r int; c int; n int; dr int; dc int; rr int; cc int; k int; win boolean := false; filled boolean := true;
begin
 select * into g from public.connect4_games where code=upper(trim(room)) for update;
 if not found or not public.c4_authorized(g,secret) then raise exception 'Room unavailable or access denied'; end if;
 player := case when g.host_token_hash=encode(extensions.digest(secret,'sha256'),'hex') then 1 else 2 end;
 if g.status <> 'playing' or g.turn <> player then raise exception 'Not your turn'; end if;
 if col is null or col < 0 or col > 6 then raise exception 'Invalid column'; end if;
 select array_agg(value::int order by ord) into b from jsonb_array_elements_text(g.board) with ordinality as x(value,ord);
 if array_length(b,1) <> 42 then raise exception 'Invalid board'; end if;
 r := -1;
 for k in reverse 5..0 loop
  if b[k*7+col+1]=0 then r:=k; exit; end if;
 end loop;
 if r=-1 then raise exception 'Column is full'; end if;
 b[r*7+col+1]:=player;
 for k in 1..4 loop
  dr:=case k when 1 then 0 when 2 then 1 when 3 then 1 else 1 end;
  dc:=case k when 1 then 1 when 2 then 0 when 3 then 1 else -1 end;
  n:=1;
  for c in -1..1 loop
   if c=0 then continue; end if;
   for rr in 1..3 loop
    if r+c*rr*dr between 0 and 5 and col+c*rr*dc between 0 and 6
      and b[(r+c*rr*dr)*7+(col+c*rr*dc)+1]=player then n:=n+1;
    else exit; end if;
   end loop;
  end loop;
  if n>=4 then win:=true; exit; end if;
 end loop;
 for k in 1..42 loop if b[k]=0 then filled:=false; exit; end if; end loop;
 update public.connect4_games set board=to_jsonb(b),winner=case when win then player when filled then 3 else 0 end,
 status=case when win or filled then 'finished' else 'playing' end,
 turn=case when player=1 then 2 else 1 end,version=version+1,updated_at=now()
 where id=g.id returning * into g;
 return public.c4_view(g,secret);
end; $$;

create or replace function public.c4_rematch(room text, secret text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare g public.connect4_games;
begin
 select * into g from public.connect4_games where code=upper(trim(room)) for update;
 if not found or not public.c4_authorized(g,secret) then raise exception 'Access denied'; end if;
 if g.status <> 'finished' then raise exception 'Finish this game first'; end if;
 update public.connect4_games set board=to_jsonb(array_fill(0,array[42])),turn=case when (g.version % 2)=0 then 1 else 2 end,
 winner=0,status='playing',version=version+1,updated_at=now() where id=g.id returning * into g;
 return public.c4_view(g,secret);
end; $$;

revoke all on function public.c4_authorized(public.connect4_games,text) from public,anon,authenticated;
revoke all on function public.c4_view(public.connect4_games,text) from public,anon,authenticated;
revoke all on function public.c4_create(text) from public;
revoke all on function public.c4_join(text,text) from public;
revoke all on function public.c4_get(text,text) from public;
revoke all on function public.c4_move(text,text,int) from public;
revoke all on function public.c4_rematch(text,text) from public;
grant execute on function public.c4_create(text),public.c4_join(text,text),public.c4_get(text,text),public.c4_move(text,text,int),public.c4_rematch(text,text) to anon,authenticated;
-- Optional cleanup: delete rooms older than 30 days periodically from SQL Editor.
