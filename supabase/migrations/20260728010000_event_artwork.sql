-- Arte del evento para el correo del ticket.
--
-- Se guarda la URL, no la imagen: los correos referencian la imagen por URL y
-- meterla como adjunto embebido (cid:) dispara filtros de spam en varios
-- proveedores.

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- -----------------------------------------------------------------------------
-- Bucket del arte
-- -----------------------------------------------------------------------------
-- Público a propósito: la imagen tiene que poder cargarse desde el cliente de
-- correo de cualquier asistente, que no está autenticado contra Supabase. Una
-- URL firmada vencería y dejaría correos viejos con la imagen rota.
INSERT INTO storage.buckets (id, name, public)
VALUES ('event-artwork', 'event-artwork', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Event artwork is readable'
  ) THEN
    CREATE POLICY "Event artwork is readable" ON storage.objects
      FOR SELECT USING (bucket_id = 'event-artwork');
  END IF;

  -- Escritura solo para usuarios autenticados. No se restringe por carpeta
  -- como en los avatares porque el arte lo sube quien administra el evento,
  -- que no es necesariamente quien lo creó.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Event artwork write'
  ) THEN
    CREATE POLICY "Event artwork write" ON storage.objects
      FOR INSERT WITH CHECK (
        bucket_id = 'event-artwork' AND auth.role() = 'authenticated'
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Event artwork update'
  ) THEN
    CREATE POLICY "Event artwork update" ON storage.objects
      FOR UPDATE USING (
        bucket_id = 'event-artwork' AND auth.role() = 'authenticated'
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Event artwork delete'
  ) THEN
    CREATE POLICY "Event artwork delete" ON storage.objects
      FOR DELETE USING (
        bucket_id = 'event-artwork' AND auth.role() = 'authenticated'
      );
  END IF;
END $$;
