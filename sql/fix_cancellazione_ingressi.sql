-- Correzione (23/11/2026): togliere un ingresso dava l'errore «record "old" has no field "eliminato_il"».
-- Il trigger lotti_segna_cancellato leggeva old.eliminato_il anche per la tabella ingressi, che non ha quella colonna.
-- Ora i due casi sono separati. Già eseguito in Supabase.
create or replace function public.lotti_segna_cancellato()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    insert into public.lotti_cancellati (tabella, rec_id) values (tg_table_name, old.id);
  elsif tg_table_name = 'lotti' then
    if old.eliminato_il is null and new.eliminato_il is not null then
      insert into public.lotti_cancellati (tabella, rec_id) values (tg_table_name, old.id);
    end if;
  end if;
  return null;
end $$;
