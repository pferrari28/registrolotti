-- =====================================================================
-- Registro lotti · «Rendi entrata singola» (23/11/2026)
-- SQL Editor → New query → incolla → Run. Si può rieseguire.
--
-- Riporta una consegna frazionata con UN SOLO ingresso a lotto normale
-- (operazione inversa di «converti in partita»):
--  * il lotto riprende i dati dell'ingresso (data, DDT, kg, forme, temp,
--    stato igienico, integrità, addetto) e la sua nota;
--  * l'ingresso viene tolto e il lotto non è più frazionato;
--  * il numero di lotto non cambia.
-- Stesse regole di blocco delle altre modifiche (dopo 10 giorni solo admin).
-- Non tocca le altre funzioni né le tabelle del programma di magazzino.
-- =====================================================================

create or replace function public.rendi_entrata_singola(p_id uuid)
returns public.lotti language plpgsql security definer set search_path = public as $$
declare r public.lotti; g public.ingressi; n integer;
begin
  perform public.lotti_chiedi_accesso();
  perform pg_advisory_xact_lock(hashtext('lotti_assegnazione'));
  select * into r from public.lotti where id = p_id and eliminato_il is null for update;
  if not found then raise exception 'Questo lotto non esiste più (è stato eliminato da un altro PC).'; end if;
  if not r.frazionata then raise exception 'Questo lotto non è una consegna frazionata.'; end if;
  perform public.lotti_controlla_modifica(p_id);
  select count(*) into n from public.ingressi where lotto_id = p_id;
  if n <> 1 then raise exception 'Si può rendere entrata singola solo una partita con un solo ingresso (questa ne ha %).', n; end if;
  select * into g from public.ingressi where lotto_id = p_id;
  update public.lotti set
    frazionata = false, data_arrivo = g.data_arrivo, ddt = g.ddt, qta_kg = g.qta_kg, qta = g.forme, um = 'f',
    temp = g.temp, igiene = g.igiene, integrita = g.integrita, addetto = g.addetto,
    note = coalesce(nullif(g.note, ''), r.note)
  where id = p_id;
  delete from public.ingressi where id = g.id;
  perform public.lotti_bump();
  select * into r from public.lotti where id = p_id;
  return r;
end $$;

revoke all on function public.rendi_entrata_singola(uuid) from public, anon;
grant execute on function public.rendi_entrata_singola(uuid) to authenticated;
