-- =====================================================================
-- Registro lotti · Sincronizzazione «solo novità» (31/10/2026)
-- SQL Editor → New query → incolla → Run. Si può rieseguire.
-- Non modifica i dati dei lotti. Non tocca il programma di magazzino.
--
-- Prima: ogni PC riscaricava tutto il registro ogni 20 secondi.
-- Dopo: ogni 20 secondi legge solo il «numero di versione» (pochi byte);
-- se è cambiato scarica solo i lotti/ingressi nuovi o modificati.
--
--  * colonna modificato_il su lotti e ingressi (aggiornata da sola);
--  * tabella lotti_cancellati: elenco dei lotti/ingressi eliminati o
--    spostati nel cestino, così gli altri PC li tolgono dalla vista
--    (si svuota da sola dopo 30 giorni);
--  * ogni modifica a lotti, ingressi, elenchi, medie, regole, serie e
--    controlli aggiorna il numero di versione (anche lo svuotamento
--    automatico del cestino).
-- =====================================================================

-- 1) quando è stata modificata l'ultima volta ogni riga
alter table public.lotti    add column if not exists modificato_il timestamptz;
alter table public.ingressi add column if not exists modificato_il timestamptz;
update public.lotti    set modificato_il = coalesce(created_at, now()) where modificato_il is null;
update public.ingressi set modificato_il = coalesce(created_at, now()) where modificato_il is null;
alter table public.lotti    alter column modificato_il set default clock_timestamp();
alter table public.ingressi alter column modificato_il set default clock_timestamp();
create index if not exists lotti_modificato_il    on public.lotti (modificato_il);
create index if not exists ingressi_modificato_il on public.ingressi (modificato_il);

create or replace function public.lotti_segna_modifica()
returns trigger language plpgsql as $$
begin
  new.modificato_il := clock_timestamp();
  return new;
end $$;

drop trigger if exists lotti_segna_modifica_trg on public.lotti;
create trigger lotti_segna_modifica_trg before insert or update on public.lotti
  for each row execute function public.lotti_segna_modifica();
drop trigger if exists ingressi_segna_modifica_trg on public.ingressi;
create trigger ingressi_segna_modifica_trg before insert or update on public.ingressi
  for each row execute function public.lotti_segna_modifica();

-- 2) elenco delle righe tolte (eliminate o spostate nel cestino)
create table if not exists public.lotti_cancellati (
  id      bigserial primary key,
  tabella text not null,
  rec_id  uuid not null,
  il      timestamptz not null default clock_timestamp()
);
create index if not exists lotti_cancellati_il on public.lotti_cancellati (il);
alter table public.lotti_cancellati enable row level security;
drop policy if exists lotti_cancellati_lettura on public.lotti_cancellati;
create policy lotti_cancellati_lettura on public.lotti_cancellati for select to authenticated
  using (public.lotti_ruolo() is not null);
grant select on public.lotti_cancellati to authenticated;
revoke insert, update, delete on public.lotti_cancellati from authenticated, anon;

create or replace function public.lotti_segna_cancellato()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE'
     or (tg_table_name = 'lotti' and old.eliminato_il is null and new.eliminato_il is not null) then
    insert into public.lotti_cancellati (tabella, rec_id) values (tg_table_name, old.id);
  end if;
  return null;
end $$;

drop trigger if exists lotti_cancellato_trg on public.lotti;
create trigger lotti_cancellato_trg after delete or update of eliminato_il on public.lotti
  for each row execute function public.lotti_segna_cancellato();
drop trigger if exists ingressi_cancellato_trg on public.ingressi;
create trigger ingressi_cancellato_trg after delete on public.ingressi
  for each row execute function public.lotti_segna_cancellato();

-- 3) ogni modifica aggiorna il numero di versione (una volta per operazione)
create or replace function public.lotti_bump_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.lotti_bump();
  if tg_table_name = 'lotti' and tg_op = 'DELETE' then
    delete from public.lotti_cancellati where il < now() - interval '30 days';
  end if;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['lotti', 'ingressi', 'lotti_voci', 'lotti_medie', 'lotti_regole', 'lotti_serie', 'lotti_verifiche'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on public.%I', t || '_bump_trg', t);
      execute format('create trigger %I after insert or update or delete on public.%I for each statement execute function public.lotti_bump_trg()', t || '_bump_trg', t);
    end if;
  end loop;
end $$;

-- 4) il «tempo reale» guarda solo il numero di versione (tabella impostazioni)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'impostazioni') then
    execute 'alter publication supabase_realtime add table public.impostazioni';
  end if;
end $$;

select public.lotti_bump();

-- controllo finale
select 'lotti' as tabella, count(*) as righe, max(modificato_il) as ultima_modifica from public.lotti
union all
select 'ingressi', count(*), max(modificato_il) from public.ingressi;
