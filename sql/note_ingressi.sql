-- =====================================================================
-- Registro lotti · Nota per ogni ingresso delle consegne frazionate (10/11/2026)
-- SQL Editor → New query → incolla → Run. Si può rieseguire.
--
-- Ogni ingresso di una consegna frazionata può avere la sua nota.
--  * colonna note sulla tabella ingressi;
--  * funzione salva_nota_ingresso: scrive la nota di un ingresso.
--    Possono usarla gli utenti registrati; per chi non è admin vale lo
--    stesso blocco dei 10 giorni dall'ultimo ingresso della partita.
-- Non modifica nessuna delle funzioni esistenti e non tocca le tabelle
-- del programma di magazzino.
-- Richiede che sia già stato eseguito utenti_paolo_qualita.sql
-- (usa lotti_is_admin).
-- =====================================================================

alter table public.ingressi add column if not exists note text;

create or replace function public.salva_nota_ingresso(p_id text, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
declare v_lotto text; v_ult date;
begin
  if auth.uid() is null then raise exception 'Accesso richiesto.'; end if;
  select lotto_id::text into v_lotto from public.ingressi where id::text = p_id;
  if v_lotto is null then raise exception 'Ingresso non trovato.'; end if;
  if not public.lotti_is_admin() then
    select max(data_arrivo)::date into v_ult from public.ingressi where lotto_id::text = v_lotto;
    if v_ult is not null and v_ult < current_date - 10 then
      raise exception 'Ingresso bloccato: sono passati più di 10 giorni dall''ultimo ingresso della partita.';
    end if;
  end if;
  update public.ingressi set note = nullif(trim(p_nota), '') where id::text = p_id;
end $$;

revoke all on function public.salva_nota_ingresso(text, text) from public, anon;
grant execute on function public.salva_nota_ingresso(text, text) to authenticated;
