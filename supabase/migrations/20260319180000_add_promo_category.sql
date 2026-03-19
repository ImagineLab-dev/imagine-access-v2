-- Add 'promo' to ticket_types category enum
-- The CHECK constraint is on ticket_types.category
ALTER TABLE public.ticket_types
  DROP CONSTRAINT IF EXISTS ticket_types_category_check;

ALTER TABLE public.ticket_types
  ADD CONSTRAINT ticket_types_category_check
  CHECK (category IN ('standard', 'guest', 'staff', 'invitation', 'promo'));

-- Add promo_qty column to ticket_types for pack size
ALTER TABLE public.ticket_types
  ADD COLUMN IF NOT EXISTS promo_qty INT DEFAULT 1;
