-- Add timezone column to events so email timestamps render in the event's local time.
-- Default to Argentina; override per-event when needed.
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'America/Argentina/Buenos_Aires';
