-- Add ticket_type_id column to tickets table (if not already present)
-- and create the FK to ticket_types so PostgREST joins work.
ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS ticket_type_id UUID REFERENCES public.ticket_types(id);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_type_id ON public.tickets(ticket_type_id);
