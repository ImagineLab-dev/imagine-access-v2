-- Add tolerance_minutes column to ticket_types
-- This allows admins to set a grace period (in minutes) for invitation tickets
-- The tolerance is NOT shown in emails, only used during validation
ALTER TABLE public.ticket_types ADD COLUMN IF NOT EXISTS tolerance_minutes INT DEFAULT 0;
