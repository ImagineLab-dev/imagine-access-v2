-- Relación tickets -> users_profile para que PostgREST pueda anidarlas.
--
-- El dashboard consulta:
--   /rest/v1/checkins?select=*,tickets(buyer_name,type,users_profile!created_by(display_name))
--
-- Eso exige una clave foránea DIRECTA entre tickets y users_profile. Hoy no
-- existe: `tickets.created_by` apunta a `auth.users(id)` y `users_profile.user_id`
-- también, así que la relación pasa por un tercero. PostgREST no atraviesa ese
-- salto —y menos hacia el esquema `auth`, que no expone— y responde
--   PGRST200: Could not find a relationship between 'tickets' and 'users_profile'
--
-- Se agrega una segunda foránea sobre la misma columna, apuntando a
-- users_profile.user_id (que es UNIQUE). No reemplaza a la existente hacia
-- auth.users: ambas son ciertas y describen la misma realidad por caminos
-- distintos. La consulta nombra la tabla destino, así que no hay ambigüedad.
--
-- ON DELETE SET NULL y no CASCADE: si se borra el perfil de quien creó un
-- ticket, el ticket tiene que sobrevivir. Es un registro de acceso vendido,
-- no un dato accesorio del usuario.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tickets_created_by_profile_fkey'
      AND conrelid = 'public.tickets'::regclass
  ) THEN
    -- Cualquier created_by que no tenga perfil se limpia primero: de lo
    -- contrario la restricción no puede crearse.
    UPDATE public.tickets t
       SET created_by = NULL
     WHERE t.created_by IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.users_profile p WHERE p.user_id = t.created_by
       );

    ALTER TABLE public.tickets
      ADD CONSTRAINT tickets_created_by_profile_fkey
      FOREIGN KEY (created_by)
      REFERENCES public.users_profile(user_id)
      ON DELETE SET NULL;
  END IF;
END $$;
