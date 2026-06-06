


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "hypopg" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "index_advisor" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."booking_status" AS ENUM (
    'pending',
    'confirmed',
    'scheduled',
    'in_progress',
    'completed',
    'cancelled',
    'en_route',
    'arrived'
);


ALTER TYPE "public"."booking_status" OWNER TO "postgres";


CREATE TYPE "public"."cleaner_status" AS ENUM (
    'pending_verification',
    'active',
    'inactive',
    'suspended'
);


ALTER TYPE "public"."cleaner_status" OWNER TO "postgres";


CREATE TYPE "public"."job_offer_status" AS ENUM (
    'sent',
    'accepted',
    'declined',
    'expired'
);


ALTER TYPE "public"."job_offer_status" OWNER TO "postgres";


CREATE TYPE "public"."job_status" AS ENUM (
    'pending',
    'offered',
    'claimed',
    'canceled',
    'expired',
    'in_progress',
    'completed'
);


ALTER TYPE "public"."job_status" OWNER TO "postgres";


CREATE TYPE "public"."notification_type" AS ENUM (
    'booking_confirmation',
    'booking_reminder',
    'booking_cancelled',
    'cleaner_assigned',
    'payment_received',
    'admin_message',
    'cleaner_en_route',
    'cleaner_arrived'
);


ALTER TYPE "public"."notification_type" OWNER TO "postgres";


CREATE TYPE "public"."service_category" AS ENUM (
    'cleaning',
    'washing',
    'ironing'
);


ALTER TYPE "public"."service_category" OWNER TO "postgres";


CREATE TYPE "public"."user_status" AS ENUM (
    'active',
    'inactive',
    'suspended',
    'pending'
);


ALTER TYPE "public"."user_status" OWNER TO "postgres";


CREATE TYPE "public"."withdrawal_status" AS ENUM (
    'pending',
    'processing',
    'success',
    'failed',
    'reversed'
);


ALTER TYPE "public"."withdrawal_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.co_cleaner_invitations%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO r
  FROM public.co_cleaner_invitations
  WHERE token = p_token
    AND status = 'pending'
    AND expires_at > now();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_or_expired_invite');
  END IF;

  IF r.inviter_user_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'cannot_accept_own_invite');
  END IF;

  IF NOT public.is_co_cleaner_invitee_eligible(v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'co_cleaner_verification_required');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.cleaner_data
    WHERE user_id = r.inviter_user_id AND verified IS TRUE
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'inviter_not_verified');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.co_cleaner_relationships AS rel
    WHERE rel.co_cleaner_id = v_uid
      AND rel.lead_cleaner_id <> r.inviter_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'co_cleaner_already_on_team');
  END IF;

  INSERT INTO public.co_cleaner_relationships (lead_cleaner_id, co_cleaner_id)
  VALUES (r.inviter_user_id, v_uid)
  ON CONFLICT (lead_cleaner_id, co_cleaner_id) DO NOTHING;

  UPDATE public.co_cleaner_invitations
  SET
    status = 'accepted',
    accepted_user_id = v_uid,
    updated_at = now()
  WHERE id = r.id;

  RETURN jsonb_build_object('success', true, 'lead_cleaner_id', r.inviter_user_id);
END;
$$;


ALTER FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.preferred_cleaner_invitations%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO r
  FROM public.preferred_cleaner_invitations
  WHERE token = p_token
    AND status = 'pending'
    AND expires_at > now();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_or_expired_invite');
  END IF;

  IF r.inviter_user_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'cannot_accept_own_invite');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.cleaner_data
    WHERE user_id = v_uid AND verified IS TRUE
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'preferred_invite_cleaner_not_verified');
  END IF;

  INSERT INTO public.preferred_cleaners (user_id, cleaner_id)
  VALUES (r.inviter_user_id, v_uid)
  ON CONFLICT (user_id, cleaner_id) DO NOTHING;

  UPDATE public.preferred_cleaner_invitations
  SET
    status = 'accepted',
    accepted_cleaner_id = v_uid,
    updated_at = now()
  WHERE id = r.id;

  RETURN jsonb_build_object(
    'success', true,
    'customer_user_id', r.inviter_user_id
  );
END;
$$;


ALTER FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_cleaner_record"("p_user_id" "uuid", "p_name" "text", "p_bio" "text", "p_avatar_url" "text", "p_status" "text", "p_verified" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_clean_name      text := trim(coalesce(p_name, ''));
  v_first_name      text;
  v_last_name       text;
  v_status          public.cleaner_status := COALESCE(NULLIF(p_status, '')::public.cleaner_status, 'active'::public.cleaner_status);
  v_verified        boolean := COALESCE(p_verified, false);
  v_now             timestamptz := now();
  v_roles_inserted  int := 0;
BEGIN
  -- Confirm public.users mirror exists.
  PERFORM 1
  FROM public.users
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_first_name := NULLIF(split_part(v_clean_name, ' ', 1), '');

  v_last_name := NULLIF(
    regexp_replace(v_clean_name, '^\S+\s*', ''),
    ''
  );

  INSERT INTO public.profiles (
    id,
    user_id,
    firstname,
    lastname,
    avatar_url,
    bio,
    updated_at
  )
  VALUES (
    p_user_id,
    p_user_id,
    v_first_name,
    v_last_name,
    NULLIF(p_avatar_url, ''),
    NULLIF(p_bio, ''),
    v_now
  )
  ON CONFLICT (id) DO UPDATE SET
    firstname  = COALESCE(NULLIF(public.profiles.firstname, ''), EXCLUDED.firstname),
    lastname   = COALESCE(NULLIF(public.profiles.lastname, ''), EXCLUDED.lastname),
    avatar_url = COALESCE(NULLIF(public.profiles.avatar_url, ''), EXCLUDED.avatar_url),
    bio        = COALESCE(NULLIF(public.profiles.bio, ''), EXCLUDED.bio),
    updated_at = v_now;

  WITH inserted_roles AS (
    INSERT INTO public.user_roles (user_id, role_id)
    VALUES
      (p_user_id, 'cleaner'),
      (p_user_id, 'customer')
    ON CONFLICT (user_id, role_id) DO NOTHING
    RETURNING role_id
  )
  SELECT count(*) INTO v_roles_inserted
  FROM inserted_roles;

  INSERT INTO public.cleaner_data (
    user_id,
    bio,
    status,
    verified,
    skills,
    languages,
    service_areas,
    equipment_owned,
    updated_at
  )
  VALUES (
    p_user_id,
    NULLIF(p_bio, ''),
    v_status,
    v_verified,
    ARRAY[]::text[],
    ARRAY['English']::text[],
    ARRAY[]::text[],
    ARRAY[]::text[],
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    bio        = COALESCE(NULLIF(EXCLUDED.bio, ''), public.cleaner_data.bio),
    status     = v_status,
    verified   = v_verified,
    updated_at = v_now;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'status', v_status,
    'verified', v_verified,
    'roles_inserted', v_roles_inserted
  );
END;
$$;


ALTER FUNCTION "public"."add_cleaner_record"("p_user_id" "uuid", "p_name" "text", "p_bio" "text", "p_avatar_url" "text", "p_status" "text", "p_verified" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."add_cleaner_record"("p_user_id" "uuid", "p_name" "text", "p_bio" "text", "p_avatar_url" "text", "p_status" "text", "p_verified" boolean) IS 'Transactionally provision the public-schema rows for an admin-added cleaner whose auth.users row already exists. Service-role only. Errors: P0002 user_not_found.';



CREATE OR REPLACE FUNCTION "public"."approve_and_complete_booking"("p_booking_id" "uuid", "p_rating" integer, "p_feedback" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- 1. Verify the booking is actually ready for approval
    IF NOT EXISTS (SELECT 1 FROM public.bookings WHERE id = p_booking_id AND status = 'awaiting_approval') THEN
        RAISE EXCEPTION 'Booking is not in a state that can be approved.';
    END IF;

    -- 2. Update the booking to final completed status
    UPDATE public.bookings
    SET 
        status = 'completed',
        updated_at = now()
    WHERE id = p_booking_id;

    -- 3. Update cleaner metrics (rating)
    UPDATE public.cleaner_data
    SET 
        rating = (rating * completed_jobs + p_rating) / (completed_jobs + 1),
        completed_jobs = completed_jobs + 1
    WHERE user_id = (SELECT cleaner_id FROM public.bookings WHERE id = p_booking_id);

    -- 4. Log final note to timeline
    INSERT INTO public.booking_timeline (booking_id, stage, notes)
    VALUES (p_booking_id, 'completed', 'Customer approved: ' || p_feedback);
END;
$$;


ALTER FUNCTION "public"."approve_and_complete_booking"("p_booking_id" "uuid", "p_rating" integer, "p_feedback" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_cleaner_application"("p_application_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_app             public.cleaner_applications%ROWTYPE;
  v_user_id         uuid;
  v_first_name      text;
  v_last_name       text;
  v_app_phone_e164  text;
  v_now             timestamptz := now();
  v_roles_inserted  int := 0;
BEGIN
  SELECT * INTO v_app
  FROM public.cleaner_applications
  WHERE id = p_application_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'application_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_app_phone_e164 := public.normalize_ghana_phone_to_e164(v_app.phone);

  v_user_id := v_app.user_id;

  IF v_user_id IS NULL AND NULLIF(trim(v_app.email), '') IS NOT NULL THEN
    SELECT id INTO v_user_id
    FROM public.users
    WHERE lower(email) = lower(trim(v_app.email))
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  IF v_user_id IS NULL AND v_app_phone_e164 IS NOT NULL THEN
    SELECT id INTO v_user_id
    FROM public.users
    WHERE public.normalize_ghana_phone_to_e164(phone) = v_app_phone_e164
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM 1
  FROM public.users
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_first_name := NULLIF(split_part(trim(coalesce(v_app.name, '')), ' ', 1), '');

  v_last_name := NULLIF(
    regexp_replace(trim(coalesce(v_app.name, '')), '^\S+\s*', ''),
    ''
  );

  INSERT INTO public.profiles (
    id,
    user_id,
    firstname,
    lastname,
    bio,
    updated_at
  )
  VALUES (
    v_user_id,
    v_user_id,
    v_first_name,
    v_last_name,
    NULLIF(v_app.bio, ''),
    v_now
  )
  ON CONFLICT (id) DO UPDATE SET
    firstname  = COALESCE(NULLIF(public.profiles.firstname, ''), EXCLUDED.firstname),
    lastname   = COALESCE(NULLIF(public.profiles.lastname, ''), EXCLUDED.lastname),
    bio        = COALESCE(NULLIF(public.profiles.bio, ''), EXCLUDED.bio),
    updated_at = v_now;

  WITH inserted_roles AS (
    INSERT INTO public.user_roles (user_id, role_id)
    VALUES
      (v_user_id, 'cleaner'),
      (v_user_id, 'customer')
    ON CONFLICT (user_id, role_id) DO NOTHING
    RETURNING role_id
  )
  SELECT count(*) INTO v_roles_inserted
  FROM inserted_roles;

  INSERT INTO public.cleaner_data (
    user_id,
    bio,
    skills,
    certifications,
    service_areas,
    hourly_rate,
    status,
    verified,
    updated_at
  )
  VALUES (
    v_user_id,
    NULLIF(v_app.bio, ''),
    v_app.skills,
    v_app.certifications,
    v_app.service_areas,
    v_app.hourly_rate,
    'active',
    true,
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    bio            = COALESCE(NULLIF(EXCLUDED.bio, ''), public.cleaner_data.bio),
    skills         = COALESCE(EXCLUDED.skills, public.cleaner_data.skills),
    certifications = COALESCE(EXCLUDED.certifications, public.cleaner_data.certifications),
    service_areas  = COALESCE(EXCLUDED.service_areas, public.cleaner_data.service_areas),
    hourly_rate    = COALESCE(EXCLUDED.hourly_rate, public.cleaner_data.hourly_rate),
    status = CASE
      WHEN public.cleaner_data.status = 'suspended'
      THEN public.cleaner_data.status
      ELSE 'active'
    END,
    verified   = true,
    updated_at = v_now;

  UPDATE public.cleaner_applications
  SET status     = 'approved',
      user_id    = v_user_id,
      updated_at = v_now
  WHERE id = p_application_id;

  RETURN jsonb_build_object(
    'user_id', v_user_id,
    'application_id', p_application_id,
    'approved_user_id', v_user_id,
    'status', 'approved',
    'roles_inserted', v_roles_inserted
  );
END;
$$;


ALTER FUNCTION "public"."approve_cleaner_application"("p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."approve_cleaner_application"("p_application_id" "uuid") IS 'Transactionally approve or repair a cleaner application. Service-role only. Errors: P0001 application_not_found, P0002 user_not_found.';



CREATE OR REPLACE FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (target_user_id, target_role_id)
  ON CONFLICT (user_id, role_id) DO NOTHING;
END;
$$;


ALTER FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text", "is_verified" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- 1. Assign the role to the user
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (target_user_id, target_role_id)
  ON CONFLICT (user_id, role_id) DO NOTHING;

  -- 2. If the role is 'cleaner', sync the verified status in cleaner_data
  IF target_role_id = 'cleaner' THEN
    INSERT INTO public.cleaner_data (user_id, verified, status)
    VALUES (target_user_id, is_verified, 'active')
    ON CONFLICT (user_id) 
    DO UPDATE SET 
      verified = EXCLUDED.verified,
      status = 'active';
  END IF;
END;
$$;


ALTER FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text", "is_verified" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."backfill_cleaner_application_approval"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_app_id     uuid;
  v_user_email text;
  v_user_phone text;
BEGIN
  SELECT email, public.normalize_ghana_phone_to_e164(phone)
  INTO v_user_email, v_user_phone
  FROM public.users
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT id INTO v_app_id
  FROM public.cleaner_applications
  WHERE COALESCE(status, 'pending') NOT IN ('rejected')
    AND (
      user_id = p_user_id
      OR (
        v_user_email IS NOT NULL
        AND NULLIF(trim(email), '') IS NOT NULL
        AND lower(email) = lower(v_user_email)
      )
      OR (
        v_user_phone IS NOT NULL
        AND public.normalize_ghana_phone_to_e164(phone) = v_user_phone
      )
    )
  ORDER BY
    CASE
      WHEN COALESCE(status, 'pending') = 'approved' THEN 2
      ELSE 1
    END,
    created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'application_not_found' USING ERRCODE = 'P0001';
  END IF;

  RETURN public.approve_cleaner_application(v_app_id);
END;
$$;


ALTER FUNCTION "public"."backfill_cleaner_application_approval"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."backfill_cleaner_application_approval"("p_user_id" "uuid") IS 'One-shot repair for users stuck after approval but missing user_roles/cleaner_data. Service-role only.';



CREATE OR REPLACE FUNCTION "public"."bookings_guard_payment_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF OLD.payment_status IS NOT DISTINCT FROM NEW.payment_status THEN
    RETURN NEW;
  END IF;

  IF NEW.payment_status IN ('paid', 'refunded', 'partially_refunded')
     AND auth.role() IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION
      'payment_status % cannot be set by client',
      NEW.payment_status
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."bookings_guard_payment_status"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."bookings_guard_payment_status"() IS 'Blocks client roles from setting paid/refunded/partially_refunded; service role only.';



CREATE OR REPLACE FUNCTION "public"."bookings_set_duration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  r record;
BEGIN
  SELECT *
  INTO r
  FROM public.calculate_booking_duration(
    NEW.home_size,
    COALESCE(NEW.extra_task_ids, '{}'::text[]),
    COALESCE(NEW.duration_adjustment, 0),
    12
  );

  IF r.computed_hours IS NULL OR r.final_hours IS NULL THEN
    RAISE EXCEPTION
      'Booking failed: duration engine returned NULL (computed_hours=%, final_hours=%).',
      r.computed_hours, r.final_hours;
  END IF;

  NEW.duration_computed := r.computed_hours;
  NEW.duration_final := r.final_hours;

  -- Keep user-provided duration_hours if present; otherwise fill it
  NEW.duration_hours := COALESCE(NEW.duration_hours, r.final_hours);

  IF NEW.duration_final <= 0 THEN
    RAISE EXCEPTION
      'Booking failed: final duration must be > 0 (final_hours=%).',
      NEW.duration_final;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."bookings_set_duration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_booking_duration"("p_home_size_id" "text", "p_extra_task_ids" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_base_hours numeric := 0;
  v_extra_hours numeric := 0;
  v_total numeric;
BEGIN
  -- Get base hours
  SELECT hours INTO v_base_hours FROM base_durations WHERE id = p_home_size_id;
  
  -- Sum extra tasks
  SELECT COALESCE(SUM(hours), 0) INTO v_extra_hours 
  FROM extra_tasks 
  WHERE id = ANY(p_extra_task_ids);
  
  v_total := v_base_hours + v_extra_hours;
  
  -- Apply business cap (Max 10 hours)
  RETURN LEAST(v_total, 10);
END;
$$;


ALTER FUNCTION "public"."calculate_booking_duration"("p_home_size_id" "text", "p_extra_task_ids" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_booking_duration"("p_home_size" "text", "p_extra_task_ids" "text"[] DEFAULT '{}'::"text"[], "p_adjustment_hours" numeric DEFAULT 0, "p_max_total_hours" numeric DEFAULT 12) RETURNS TABLE("computed_hours" numeric, "extras_hours" numeric, "adjustment_hours" numeric, "final_hours" numeric)
    LANGUAGE "plpgsql" STABLE
    AS $$
declare
  _base_hours numeric := 0;
  _extras_sum numeric := 0;
  _adj numeric := 0;
  _computed numeric := 0;
  _final numeric := 0;
begin
  -- Fetch base hours from lookup table
  select coalesce(h.base_hours, 0) into _base_hours
  from public.home_size_durations h
  where h.home_size = p_home_size;

  -- Sum up hours for all selected extra tasks
  select coalesce(sum(t.hours), 0) into _extras_sum
  from public.extra_tasks t
  where t.id = any(p_extra_task_ids);

  _computed := _base_hours + _extras_sum;

  -- Clamp the adjustment to ensure final hours stay within 0 and max_total_hours
  _adj := greatest(
            least(p_adjustment_hours, p_max_total_hours - _computed),
            -_computed
          );

  _final := _computed + _adj;

  return query 
  select 
    round(_computed::numeric, 1)::numeric(3,1),
    round(_extras_sum::numeric, 1)::numeric(3,1),
    round(_adj::numeric, 1)::numeric(3,1),
    round(_final::numeric, 1)::numeric(3,1);
end;
$$;


ALTER FUNCTION "public"."calculate_booking_duration"("p_home_size" "text", "p_extra_task_ids" "text"[], "p_adjustment_hours" numeric, "p_max_total_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_booking_period"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_tz text;
BEGIN
  IF NEW.scheduled_date IS NOT NULL AND NEW.scheduled_time IS NOT NULL THEN
    v_tz := COALESCE(NULLIF(trim(NEW.timezone), ''), 'UTC');
    NEW.booking_period := tstzrange(
      (NEW.scheduled_date + NEW.scheduled_time)::timestamp AT TIME ZONE v_tz,
      (NEW.scheduled_date + NEW.scheduled_time + (COALESCE(NEW.duration_hours, 2) || ' hours')::interval)::timestamp AT TIME ZONE v_tz,
      '[)'
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."calculate_booking_period"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT
    -- Cleaner viewing customer via bookings
    EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.cleaner_id = (SELECT auth.uid())
        AND b.customer_id = target_user
    )
    OR
    -- Customer viewing cleaner via bookings; ensure target_user is a cleaner
    EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.customer_id = (SELECT auth.uid())
        AND b.cleaner_id = target_user
        AND EXISTS (
          SELECT 1 FROM public.cleaner_data cd
          WHERE cd.user_id = target_user
        )
    );
$$;


ALTER FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_job"("p_job_id" "uuid", "p_cleaner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_job jobs%ROWTYPE;
  v_offer_exists boolean;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_cleaner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  SELECT * INTO v_job FROM jobs WHERE id = p_job_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'job_not_found');
  END IF;

  IF v_job.status NOT IN ('pending', 'offered') OR v_job.claimed_by IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'job_not_available');
  END IF;

  IF v_job.offer_expires_at IS NOT NULL AND v_job.offer_expires_at < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'offer_expired');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM job_offers
    WHERE job_id = p_job_id AND cleaner_id = p_cleaner_id AND status = 'sent'
  ) INTO v_offer_exists;

  IF NOT v_offer_exists THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_offer');
  END IF;

  UPDATE jobs
  SET status = 'claimed', claimed_by = p_cleaner_id, claimed_at = now()
  WHERE id = p_job_id;

  UPDATE job_offers
  SET status = 'accepted', responded_at = now()
  WHERE job_id = p_job_id AND cleaner_id = p_cleaner_id;

  UPDATE job_offers
  SET status = 'expired'
  WHERE job_id = p_job_id AND cleaner_id <> p_cleaner_id;

  RETURN jsonb_build_object(
    'success', true,
    'job', to_jsonb((SELECT j FROM jobs j WHERE j.id = p_job_id))
  );
END;
$$;


ALTER FUNCTION "public"."claim_job"("p_job_id" "uuid", "p_cleaner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text" DEFAULT NULL::"text", "p_is_recurring" boolean DEFAULT false) RETURNS TABLE("pricing_version" "text", "currency" "text", "same_day_surcharge_bps" integer, "weekend_surcharge_bps" integer, "recurring_weekly_discount_bps" integer, "recurring_monthly_discount_bps" integer, "work_rate_ghs_per_hour" numeric, "duration_hours" numeric, "subtotal_labor_major" numeric, "platform_fee_major" numeric, "booking_cover_major" numeric, "core_amount_minor" bigint, "same_day_surcharge_minor" bigint, "weekend_surcharge_minor" bigint, "recurring_discount_minor" bigint, "final_amount_minor" bigint, "recurring_amount_minor" bigint, "first_charge_amount_minor" bigint, "discount_rate_bps" integer, "is_same_day" boolean, "is_weekend" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$DECLARE
  v_now timestamptz := now();
  -- Stage 6 / 7: calendar math uses this IANA zone (default Accra if blank).
  v_tz text := COALESCE(NULLIF(trim(p_service_timezone), ''), 'Africa/Accra');
  v_min_dur numeric := 3.5;
  v_max_dur numeric := 10;
  v_stepped numeric;
  v_dur numeric;
  v_base numeric;
  v_rate numeric;
  v_disc_amount numeric;
  v_st RECORD;
  v_rule RECORD;
  v_pf_pct numeric := 15;
  v_cover numeric := 21;
  v_subtotal numeric;
  v_pf numeric;
  v_core bigint;
  v_same bigint := 0;
  v_wknd bigint := 0;
  v_after_same bigint;
  v_final bigint;
  v_today date;
  v_isodow int;
  v_same_day boolean := false;
  v_weekend boolean := false;
  v_bps_same int;
  v_bps_wknd int;
  v_bps_rw int;
  v_bps_rm int;
  v_disc_rate int;
  v_recurring bigint;
  v_first bigint;
  v_recurring_disc bigint := 0;
  v_pf_setting numeric;
  v_cover_setting numeric;
BEGIN
  -- ---------------------------------------------------------------------------
  -- Stage 0: validate service id (caller must pass a positive service_types.id).
  -- ---------------------------------------------------------------------------
  IF p_service_id IS NULL OR p_service_id <= 0 THEN
    RAISE EXCEPTION 'Invalid service id';
  END IF;

  -- ---------------------------------------------------------------------------
  -- Stage 1: billable duration — match clampBookingDurationHours() in TS.
  -- Round to nearest 0.5h, then clamp to [3.5, 10] (MIN/MAX_DURATION_HOURS).
  -- ---------------------------------------------------------------------------
  v_stepped := round(p_duration_hours_raw::numeric * 2) / 2;
  v_dur := greatest(v_min_dur, least(v_max_dur, v_stepped));

  -- ---------------------------------------------------------------------------
  -- Stage 2: base hourly rate from service_types.price.
  -- Reject inactive or missing services (same as fetchEffectiveHourlyRateGhs).
  -- ---------------------------------------------------------------------------
  SELECT s.price, s.active INTO v_st
  FROM public.service_types s
  WHERE s.id = p_service_id;

  IF NOT FOUND OR v_st.active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Invalid or inactive service';
  END IF;

  v_base := v_st.price::numeric;
  IF v_base IS NULL OR v_base < 0 THEN
    RAISE EXCEPTION 'Invalid service price';
  END IF;

  -- ---------------------------------------------------------------------------
  -- Stage 3: optional percentage discount from discounts (active, date window).
  -- If a row matches: effective rate = round(base * (1 - amount/100), 2) like TS.
  -- Window: valid_from <= now <= valid_to (both ends required, same as web query).
  -- ---------------------------------------------------------------------------
  SELECT d.amount INTO v_disc_amount
  FROM public.discounts d
  WHERE d.active = true
    AND d.service_type_id = p_service_id
    AND d.valid_from IS NOT NULL
    AND d.valid_to IS NOT NULL
    AND d.valid_from <= v_now
    AND d.valid_to >= v_now
  ORDER BY d.id DESC
  LIMIT 1;

  IF FOUND AND v_disc_amount IS NOT NULL THEN
    v_rate := round((v_base * (1 - (v_disc_amount::numeric / 100)))::numeric, 2);
  ELSE
    v_rate := v_base;
  END IF;

  -- ---------------------------------------------------------------------------
  -- Stage 4: active pricing rule (bps for surcharges + recurring discounts).
  -- Same source as get_active_pricing_rule: one row with active = true.
  -- If none: fall back to v1 constants (500/500/700/1200 bps) like FALLBACK_ACTIVE_PRICING_RULE_V1.
  -- Output columns also expose the bps so clients can build ActivePricingRule.
  -- ---------------------------------------------------------------------------
  SELECT
    r.pricing_version,
    r.currency,
    r.same_day_surcharge_bps,
    r.weekend_surcharge_bps,
    r.recurring_weekly_discount_bps,
    r.recurring_monthly_discount_bps
  INTO v_rule
  FROM public.pricing_rules r
  WHERE r.is_active = true
  ORDER BY r.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    pricing_version := 'v1';
    currency := 'GHS';
    v_bps_same := 500;
    v_bps_wknd := 500;
    v_bps_rw := 700;
    v_bps_rm := 1200;
  ELSE
    pricing_version := v_rule.pricing_version;
    currency := v_rule.currency;
    v_bps_same := least(10000, greatest(0, coalesce(v_rule.same_day_surcharge_bps, 500)));
    v_bps_wknd := least(10000, greatest(0, coalesce(v_rule.weekend_surcharge_bps, 500)));
    v_bps_rw := least(10000, greatest(0, coalesce(v_rule.recurring_weekly_discount_bps, 700)));
    v_bps_rm := least(10000, greatest(0, coalesce(v_rule.recurring_monthly_discount_bps, 1200)));
  END IF;

  same_day_surcharge_bps := v_bps_same;
  weekend_surcharge_bps := v_bps_wknd;
  recurring_weekly_discount_bps := v_bps_rw;
  recurring_monthly_discount_bps := v_bps_rm;

  -- ---------------------------------------------------------------------------
  -- Stage 5: booking_settings — platform fee % of labor + booking cover (GHS).
  -- Keys: platform_fee_percentage (whole percent, default 15), booking_cover_amount (default 21).
  -- Matches fetchBookingSettingsPricingKv().
  -- ---------------------------------------------------------------------------
  SELECT bs.value_numeric INTO v_pf_setting
  FROM public.booking_settings bs
  WHERE bs.key = 'platform_fee_percentage'
  LIMIT 1;

  SELECT bs.value_numeric INTO v_cover_setting
  FROM public.booking_settings bs
  WHERE bs.key = 'booking_cover_amount'
  LIMIT 1;

  IF v_pf_setting IS NOT NULL AND v_pf_setting >= 0 THEN
    v_pf_pct := least(100::numeric, greatest(0::numeric, v_pf_setting::numeric));
  END IF;

  IF v_cover_setting IS NOT NULL AND v_cover_setting >= 0 THEN
    v_cover := v_cover_setting::numeric;
  END IF;

  -- ---------------------------------------------------------------------------
  -- Stage 6: labor subtotal, platform fee (on labor only), core in minor units.
  -- subtotal_labor = rate * duration; platform_fee = subtotal * (pct/100);
  -- core_amount_minor = round((subtotal + platform_fee + cover) * 100) — computeCoreAmountMinor.
  -- ---------------------------------------------------------------------------
  v_subtotal := greatest(0::numeric, v_rate * v_dur);
  v_pf := (v_subtotal * least(100::numeric, greatest(0::numeric, v_pf_pct))) / 100::numeric;
  v_core := round(greatest(0::numeric, v_subtotal + v_pf + v_cover) * 100)::bigint;

  -- ---------------------------------------------------------------------------
  -- Stage 7: same-day vs weekend in the service timezone (applyRuleSurchargesMinor).
  -- "Today" in zone: compare p_scheduled_date to (now() rendered in v_tz)::date.
  -- Weekday: ISO DOW 1–7 Mon–Sun at local civil date for noon UTC on p_scheduled_date
  -- (matches date-fns getIsoWeekdayInServiceTz anchor).
  -- Same-day surcharge: bps on core. Weekend: bps on (core + same_day_surcharge_minor).
  -- ---------------------------------------------------------------------------
  v_today := (timezone(v_tz, v_now))::date;
  v_same_day := (p_scheduled_date = v_today);

  v_isodow := EXTRACT(
    ISODOW FROM (
      ((p_scheduled_date::timestamp + interval '12 hours') AT TIME ZONE 'UTC') AT TIME ZONE v_tz
    )
  )::int;

  v_weekend := (v_isodow IN (6, 7));

  IF v_same_day THEN
    v_same := round((v_core::numeric * v_bps_same::numeric) / 10000.0)::bigint;
  ELSE
    v_same := 0;
  END IF;

  v_after_same := v_core + v_same;

  IF v_weekend THEN
    v_wknd := round((v_after_same::numeric * v_bps_wknd::numeric) / 10000.0)::bigint;
  ELSE
    v_wknd := 0;
  END IF;

  v_final := v_core + v_same + v_wknd;

  -- ---------------------------------------------------------------------------
  -- Stage 8: recurring subscription (optional).
  -- If p_is_recurring and interval set: discount bps on core from rule — monthly uses
  -- recurring_monthly_discount_bps; weekly and bi-weekly use recurring_weekly_discount_bps.
  -- recurring_amount_minor = round(core * (10000 - bps) / 10000).
  -- first_charge_amount_minor = final_amount after surcharges (first visit pays full).
  -- recurring_discount_minor = max(0, core - recurring_amount_minor).
  -- ---------------------------------------------------------------------------
  IF p_is_recurring AND p_recurrence_interval IS NOT NULL THEN
    IF lower(trim(p_recurrence_interval)) = 'monthly' THEN
      v_disc_rate := v_bps_rm;
    ELSE
      v_disc_rate := v_bps_rw;
    END IF;
    v_disc_rate := least(10000, greatest(0, v_disc_rate));
    v_recurring := round((v_core::numeric * (10000 - v_disc_rate)::numeric) / 10000.0)::bigint;
    v_first := v_final;
    v_recurring_disc := greatest(0::bigint, v_core - v_recurring);
  ELSE
    v_disc_rate := NULL;
    v_recurring := NULL;
    v_first := NULL;
    v_recurring_disc := 0;
  END IF;

  -- ---------------------------------------------------------------------------
  -- Stage 9: fill RETURNS TABLE (one row).
  -- ---------------------------------------------------------------------------
  work_rate_ghs_per_hour := v_rate;
  duration_hours := v_dur;
  subtotal_labor_major := v_subtotal;
  platform_fee_major := v_pf;
  booking_cover_major := v_cover;
  core_amount_minor := v_core;
  same_day_surcharge_minor := v_same;
  weekend_surcharge_minor := v_wknd;
  recurring_discount_minor := v_recurring_disc;
  final_amount_minor := v_final;
  recurring_amount_minor := v_recurring;
  first_charge_amount_minor := v_first;
  discount_rate_bps := v_disc_rate;
  is_same_day := v_same_day;
  is_weekend := v_weekend;

  RETURN NEXT;
END;$$;


ALTER FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text", "p_is_recurring" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text", "p_is_recurring" boolean) IS 'Authoritative booking quote: duration clamp, service rate + discounts, pricing_rules bps, booking_settings fee/cover, core minor, TZ surcharges, recurring. See migration header for stages.';



CREATE OR REPLACE FUNCTION "public"."compute_booking_scheduled_at_utc"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.scheduled_date is null or new.scheduled_time is null then
    new.scheduled_at_utc := null;
  else
    new.scheduled_at_utc :=
      ((new.scheduled_date::date + new.scheduled_time::time)
        at time zone coalesce(nullif(new.timezone_name, ''), 'Africa/Accra'));
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."compute_booking_scheduled_at_utc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_ghana_phone_variants"("raw_phone" "text") RETURNS TABLE("phone_e164" "text", "phone_variants" "text"[])
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
declare
  cleaned text;
  digits text;
  national text;
begin
  cleaned := nullif(regexp_replace(coalesce(raw_phone, ''), '[[:space:]-]', '', 'g'), '');

  if cleaned is null or position('@' in cleaned) > 0 then
    return query select null::text, '{}'::text[];
    return;
  end if;

  digits := case
    when left(cleaned, 1) = '+' then substring(cleaned from 2)
    else cleaned
  end;

  if digits !~ '^\d+$' then
    return query select null::text, '{}'::text[];
    return;
  end if;

  if digits like '233%' and char_length(digits) >= 12 then
    phone_e164 := '+' || digits;
  elsif digits like '0%' and char_length(digits) = 10 then
    phone_e164 := '+233' || substring(digits from 2);
  elsif char_length(digits) = 9 then
    phone_e164 := '+233' || digits;
  else
    return query
    select cleaned, array[cleaned]::text[];
    return;
  end if;

  digits := substring(phone_e164 from 2);
  national := case
    when digits like '233%' then substring(digits from 4)
    else digits
  end;

  phone_variants := array(
    select distinct variant
    from unnest(
      array[
        phone_e164,
        digits,
        national,
        '0' || national
      ]
    ) as variant
    where variant is not null and variant <> ''
  );

  return next;
end;
$_$;


ALTER FUNCTION "public"."compute_ghana_phone_variants"("raw_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text" DEFAULT NULL::"text", "p_invitee_phone_e164" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token uuid := gen_random_uuid();
  v_expires timestamptz := now() + interval '30 days';
  v_id uuid;
  v_email text := NULLIF(lower(trim(COALESCE(p_invitee_email, ''))), '');
  v_phone text := NULLIF(trim(COALESCE(p_invitee_phone_e164, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.cleaner_data
    WHERE user_id = v_uid AND verified IS TRUE
  ) THEN
    RAISE EXCEPTION 'only_verified_cleaners_can_invite';
  END IF;

  INSERT INTO public.co_cleaner_invitations (
    inviter_user_id, token, invitee_email, invitee_phone_e164, expires_at
  )
  VALUES (v_uid, v_token, v_email, v_phone, v_expires)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'token', v_token,
    'invite_id', v_id,
    'expires_at', v_expires
  );
END;
$$;


ALTER FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text" DEFAULT NULL::"text", "p_invitee_phone_e164" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token uuid := gen_random_uuid();
  v_expires timestamptz := now() + interval '30 days';
  v_id uuid;
  v_email text := NULLIF(lower(trim(COALESCE(p_invitee_email, ''))), '');
  v_phone text := NULLIF(trim(COALESCE(p_invitee_phone_e164, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  INSERT INTO public.preferred_cleaner_invitations (
    inviter_user_id, token, invitee_email, invitee_phone_e164, expires_at
  )
  VALUES (v_uid, v_token, v_email, v_phone, v_expires)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'token', v_token,
    'invite_id', v_id,
    'expires_at', v_expires
  );
END;
$$;


ALTER FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.bookings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_booking_id');
  END IF;

  SELECT * INTO v_row
  FROM public.bookings
  WHERE id = p_booking_id
    AND cleaner_id = v_uid
    AND status IN ('confirmed', 'scheduled')
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_declinable');
  END IF;

  UPDATE public.bookings
  SET
    status = 'cancelled',
    updated_at = now()
  WHERE id = p_booking_id;

  IF v_row.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, message, data)
    VALUES (
      v_row.customer_id,
      'booking_cancelled',
      'Booking cancelled',
      'Your cleaner had to decline this job. Please book again or contact support if you need help.',
      jsonb_build_object(
        'booking_id', p_booking_id,
        'declined_by_cleaner_id', v_uid,
        'reason', NULLIF(trim(p_reason), '')
      )
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking_id);
END;
$$;


ALTER FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_single_default_platform_fee"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- If the new row is being set as default, unset all other defaults
  IF NEW.is_default = TRUE THEN
    UPDATE public.platform_fees
    SET is_default = FALSE
    WHERE id != NEW.id AND is_default = TRUE;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."ensure_single_default_platform_fee"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_stale_pending_bookings"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  affected integer;
  v_now timestamptz := now();
BEGIN
  UPDATE public.bookings
  SET
    status = 'cancelled'::booking_status,
    updated_at = v_now
  WHERE status = 'pending'::booking_status
    AND payment_status = 'pending'
    AND subscription_id IS NULL
    AND created_at < (v_now - interval '48 hours')
    AND updated_at < (v_now - interval '48 hours');

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;


ALTER FUNCTION "public"."expire_stale_pending_bookings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fetch_cleaner_earnings"("p_user_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_total_deduction_rate numeric;
    v_fixed_deductions numeric;
    v_in_transit numeric;
    v_estimated numeric;
    v_total numeric;
BEGIN
    -- 1. Calculate the sum of all active percentage-based and fixed rules
    SELECT 
        COALESCE(SUM(rate_percentage), 0) / 100, 
        COALESCE(SUM(fixed_amount), 0)
    INTO v_total_deduction_rate, v_fixed_deductions
    FROM public.deduction_rules 
    WHERE is_active = true AND end_date IS NULL;

    -- 2. In Transit: Gross amount minus dynamic deductions
    -- Money from jobs PAID but not yet COMPLETED
    SELECT COALESCE(
        SUM(total_price - (total_price * v_total_deduction_rate) - v_fixed_deductions), 
        0
    ) INTO v_in_transit 
    FROM public.bookings 
    WHERE cleaner_id = p_user_id 
    AND payment_status = 'paid' 
    AND status != 'completed';

    -- 3. Estimated Payout: Current actual balance in the wallet
    SELECT COALESCE(balance_subunit, 0) INTO v_estimated 
    FROM public.wallets 
    WHERE user_id = p_user_id;

    -- 4. Total Earnings: Sum of all completed credit transactions in date range
    SELECT COALESCE(SUM(amount_subunit), 0) INTO v_total 
    FROM public.wallet_transactions 
    WHERE wallet_id = (SELECT id FROM wallets WHERE user_id = p_user_id)
    AND type = 'credit'
    AND created_at BETWEEN p_start_date AND p_end_date;

    RETURN json_build_object(
        'inTransit', ROUND(v_in_transit),
        'estimatedPayout', v_estimated,
        'total', v_total
    );
END;
$$;


ALTER FUNCTION "public"."fetch_cleaner_earnings"("p_user_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_create_wallet_for_new_cleaner"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    INSERT INTO public.wallets (user_id, balance_subunit, currency)
    VALUES (NEW.user_id, 0, 'GHS')
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_create_wallet_for_new_cleaner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_finalize_withdrawal"("p_transfer_reference" "text", "p_status" "public"."withdrawal_status", "p_error_msg" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_request_record RECORD;
BEGIN
    -- 1. Find the pending request
    SELECT * INTO v_request_record 
    FROM public.withdrawal_requests 
    WHERE id = p_transfer_reference::UUID -- We used our DB ID as the reference
    FOR UPDATE; -- Lock the row for safety

    IF v_request_record IS NULL THEN
        RAISE EXCEPTION 'Withdrawal request not found';
    END IF;

    -- 2. If Success: Update Request, Debit Wallet, Log Transaction
    IF p_status = 'success' THEN
        
        -- Update the request status
        UPDATE public.withdrawal_requests 
        SET status = 'success', updated_at = NOW() 
        WHERE id = v_request_record.id;

        -- Debit the actual wallet
        UPDATE public.wallets 
        SET balance_subunit = balance_subunit - v_request_record.amount_subunit,
            updated_at = NOW()
        WHERE id = v_request_record.wallet_id;

        -- Create the audit trail (The Debit)
        INSERT INTO public.wallet_transactions (
            wallet_id, amount_subunit, type, description
        ) VALUES (
            v_request_record.wallet_id, 
            v_request_record.amount_subunit, 
            'debit', 
            'Bank Transfer Payout (Ref: ' || v_request_record.paystack_transfer_code || ')'
        );

    -- 3. If Failed: Just update the request status so they can try again
    ELSIF p_status = 'failed' THEN
        UPDATE public.withdrawal_requests 
        SET status = 'failed', error_message = p_error_msg, updated_at = NOW() 
        WHERE id = v_request_record.id;
    END IF;

END;
$$;


ALTER FUNCTION "public"."fn_finalize_withdrawal"("p_transfer_reference" "text", "p_status" "public"."withdrawal_status", "p_error_msg" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_log_status_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Only insert if the status has actually changed
    IF (OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO public.booking_timeline (booking_id, stage, notes)
        VALUES (
            NEW.id, 
            NEW.status, 
            'Status transitioned from ' || OLD.status::text || ' to ' || NEW.status::text
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_log_status_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_sync_profile_fullname"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN 
    NEW.fullname := TRIM(CONCAT(COALESCE(NEW.firstname, ''), ' ', COALESCE(NEW.lastname, '')));
    RETURN NEW;
END;$$;


ALTER FUNCTION "public"."fn_sync_profile_fullname"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_update_deduction_rule"("p_rule_name" "text", "p_new_rate" numeric, "p_is_fixed" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- 1. Retire the currently active rule
    UPDATE public.deduction_rules 
    SET 
        end_date = NOW(), 
        is_active = false 
    WHERE 
        name = p_rule_name 
        AND is_active = true;

    -- 2. Insert the new version of the rule
    INSERT INTO public.deduction_rules (
        name, 
        rate_percentage, 
        is_fixed_amount, 
        start_date, 
        is_active
    )
    VALUES (
        p_rule_name, 
        CASE WHEN p_is_fixed THEN 0 ELSE p_new_rate END,
        p_is_fixed,
        NOW(),
        true
    );
END;
$$;


ALTER FUNCTION "public"."fn_update_deduction_rule"("p_rule_name" "text", "p_new_rate" numeric, "p_is_fixed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_active_pricing_rule"() RETURNS TABLE("pricing_version" "text", "currency" "text", "same_day_surcharge_bps" integer, "weekend_surcharge_bps" integer, "recurring_weekly_discount_bps" integer, "recurring_monthly_discount_bps" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    pr.pricing_version,
    pr.currency,
    pr.same_day_surcharge_bps,
    pr.weekend_surcharge_bps,
    pr.recurring_weekly_discount_bps,
    pr.recurring_monthly_discount_bps
  FROM public.pricing_rules pr
  WHERE pr.is_active = true
    AND (pr.effective_from IS NULL OR pr.effective_from <= now())
    AND (pr.effective_to IS NULL OR pr.effective_to > now())
  ORDER BY pr.updated_at DESC
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_active_pricing_rule"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_available_booking_days"("p_timezone" "text" DEFAULT 'UTC'::"text", "p_duration_hours" numeric DEFAULT 3.0, "p_days_ahead" integer DEFAULT 14) RETURNS TABLE("booking_date" "date")
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_today date;
BEGIN
  v_today := (now() AT TIME ZONE p_timezone)::date;

  RETURN QUERY
  SELECT d::date
  FROM generate_series(
    v_today,
    v_today + (p_days_ahead - 1),
    interval '1 day'
  ) d
  WHERE EXISTS (
    SELECT 1
    FROM public.get_available_timeslots(
      d::date,
      p_timezone,
      p_duration_hours
    )
  );
END;
$$;


ALTER FUNCTION "public"."get_available_booking_days"("p_timezone" "text", "p_duration_hours" numeric, "p_days_ahead" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_available_timeslots"("p_booking_date" "date", "p_timezone" "text" DEFAULT 'UTC'::"text", "p_duration_hours" numeric DEFAULT NULL::numeric, "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("time_12h" "text", "time_24h" "text", "same_day_cutoff" numeric, "travel_buffer" numeric, "work_day_start" numeric, "work_day_end" numeric, "slot_interval_minutes" integer, "duration_hours" numeric, "disable_same_day_booking" boolean, "is_meta_row" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_same_day_cutoff numeric;
  v_travel_buffer numeric;
  v_work_day_start numeric;
  v_work_day_end numeric;

  v_slot_interval_minutes int := 30;

  v_duration numeric;
  v_now_local timestamp;

  v_start_minute int;
  v_latest_start_minute int;

  v_disable_same_day_booking boolean;
BEGIN
  -- p_exclude_booking_id: accepted for client RPC compatibility (slot list uses work-hour rules only).

  SELECT value_numeric INTO v_same_day_cutoff
  FROM booking_settings
  WHERE key = 'same_day_cutoff';

  SELECT value_numeric INTO v_travel_buffer
  FROM booking_settings
  WHERE key = 'travel_buffer';

  SELECT value_numeric INTO v_work_day_start
  FROM booking_settings
  WHERE key = 'work_day_start';

  SELECT value_numeric INTO v_work_day_end
  FROM booking_settings
  WHERE key = 'work_day_end';

  v_same_day_cutoff := COALESCE(v_same_day_cutoff, 24.0);
  v_travel_buffer   := COALESCE(v_travel_buffer, 1.0);
  v_work_day_start  := COALESCE(v_work_day_start, 5.0);
  v_work_day_end    := COALESCE(v_work_day_end, 17.0);

  v_duration := COALESCE(p_duration_hours, 3.0);

  IF v_duration <= 0 OR v_duration > 12 THEN
    RETURN QUERY
    SELECT
      NULL::text,
      NULL::text,
      v_same_day_cutoff,
      v_travel_buffer,
      v_work_day_start,
      v_work_day_end,
      v_slot_interval_minutes,
      v_duration,
      false,
      true;
    RETURN;
  END IF;

  v_now_local := now() AT TIME ZONE p_timezone;

  v_disable_same_day_booking :=
    p_booking_date = v_now_local::date
    AND (
      EXTRACT(HOUR FROM v_now_local)
      + EXTRACT(MINUTE FROM v_now_local) / 60.0
    ) >= v_same_day_cutoff;

  v_start_minute := floor(v_work_day_start * 60)::int;
  v_latest_start_minute :=
    floor((v_work_day_end - v_duration - v_travel_buffer) * 60)::int;

  RETURN QUERY
  WITH candidates AS (
    SELECT generate_series(
      v_start_minute,
      v_latest_start_minute,
      v_slot_interval_minutes
    ) AS minute_of_day
    WHERE v_latest_start_minute >= v_start_minute
  ),
  labeled AS (
    SELECT
      minute_of_day,
      (minute_of_day / 60)::int AS h24,
      (minute_of_day % 60)::int AS m
    FROM candidates
  ),
  stamped AS (
    SELECT
      (p_booking_date::timestamp
        + (h24 * interval '1 hour')
        + (m  * interval '1 minute')) AS ts,
      h24, m
    FROM labeled
  ),
  formatted AS (
    SELECT
      to_char(ts, 'FMHH12:MI AM') AS time_12h,
      to_char(ts, 'HH24:MI')      AS time_24h,
      h24, m
    FROM stamped
  ),
  slots AS (
    SELECT
      f.time_12h,
      f.time_24h,
      v_same_day_cutoff           AS same_day_cutoff,
      v_travel_buffer             AS travel_buffer,
      v_work_day_start            AS work_day_start,
      v_work_day_end              AS work_day_end,
      v_slot_interval_minutes     AS slot_interval_minutes,
      v_duration                  AS duration_hours,
      v_disable_same_day_booking  AS disable_same_day_booking,
      false                       AS is_meta_row,
      (f.h24 * 60 + f.m)          AS sort_key
    FROM formatted f
    WHERE
      NOT v_disable_same_day_booking
      AND public.validate_booking_timeslot_24h(
        f.time_24h,
        v_duration,
        p_booking_date,
        p_timezone
      ) = true
  ),
  unioned AS (
    SELECT
      s.time_12h,
      s.time_24h,
      s.same_day_cutoff,
      s.travel_buffer,
      s.work_day_start,
      s.work_day_end,
      s.slot_interval_minutes,
      s.duration_hours,
      s.disable_same_day_booking,
      s.is_meta_row,
      s.sort_key
    FROM slots s

    UNION ALL

    SELECT
      NULL::text AS time_12h,
      NULL::text AS time_24h,
      v_same_day_cutoff,
      v_travel_buffer,
      v_work_day_start,
      v_work_day_end,
      v_slot_interval_minutes,
      v_duration,
      v_disable_same_day_booking,
      true AS is_meta_row,
      NULL::int AS sort_key
    WHERE NOT EXISTS (SELECT 1 FROM slots)
  )
  SELECT
    u.time_12h,
    u.time_24h,
    u.same_day_cutoff,
    u.travel_buffer,
    u.work_day_start,
    u.work_day_end,
    u.slot_interval_minutes,
    u.duration_hours,
    u.disable_same_day_booking,
    u.is_meta_row
  FROM unioned u
  ORDER BY u.sort_key NULLS LAST;
END;
$$;


ALTER FUNCTION "public"."get_available_timeslots"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric, "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_available_timeslots_old"("p_booking_date" "date", "p_timezone" "text" DEFAULT 'UTC'::"text", "p_duration_hours" numeric DEFAULT NULL::numeric) RETURNS TABLE("time_12h" "text", "time_24h" "text", "same_day_cutoff" numeric, "travel_buffer" numeric, "work_day_start" numeric, "work_day_end" numeric, "slot_interval_minutes" integer, "duration_hours" numeric, "disable_same_day_booking" boolean, "is_meta_row" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_same_day_cutoff numeric;
  v_travel_buffer numeric;
  v_work_day_start numeric;
  v_work_day_end numeric;

  v_slot_interval_minutes int := 30;

  v_duration numeric;
  v_now_local timestamp;

  v_start_minute int;
  v_latest_start_minute int;

  v_disable_same_day_booking boolean;
BEGIN
  -- 1) Settings
  SELECT value_numeric INTO v_same_day_cutoff
  FROM booking_settings
  WHERE key = 'same_day_cutoff';

  SELECT value_numeric INTO v_travel_buffer
  FROM booking_settings
  WHERE key = 'travel_buffer';

  SELECT value_numeric INTO v_work_day_start
  FROM booking_settings
  WHERE key = 'work_day_start';

  SELECT value_numeric INTO v_work_day_end
  FROM booking_settings
  WHERE key = 'work_day_end';

  v_same_day_cutoff := COALESCE(v_same_day_cutoff, 24.0);
  v_travel_buffer   := COALESCE(v_travel_buffer, 1.0);
  v_work_day_start  := COALESCE(v_work_day_start, 5.0);
  v_work_day_end    := COALESCE(v_work_day_end, 17.0);

  -- 2) Duration
  v_duration := COALESCE(p_duration_hours, 3.0);

  IF v_duration <= 0 OR v_duration > 12 THEN
    RETURN QUERY
    SELECT
      NULL::text,
      NULL::text,
      v_same_day_cutoff,
      v_travel_buffer,
      v_work_day_start,
      v_work_day_end,
      v_slot_interval_minutes,
      v_duration,
      false,
      true;
    RETURN;
  END IF;

  -- 3) Local "now"
  v_now_local := now() AT TIME ZONE p_timezone;

  -- 4) Same-day cutoff (computed once)
  v_disable_same_day_booking :=
    p_booking_date = v_now_local::date
    AND (
      EXTRACT(HOUR FROM v_now_local)
      + EXTRACT(MINUTE FROM v_now_local) / 60.0
    ) >= v_same_day_cutoff;

  -- 5) Minute bounds
  v_start_minute := floor(v_work_day_start * 60)::int;

  -- Latest allowed start so (start + duration + buffer) <= work_day_end
  v_latest_start_minute :=
    floor((v_work_day_end - v_duration - v_travel_buffer) * 60)::int;

  -- 6) Return slots (or a meta-only row if none)
  RETURN QUERY
  WITH candidates AS (
    SELECT generate_series(
      v_start_minute,
      v_latest_start_minute,
      v_slot_interval_minutes
    ) AS minute_of_day
    WHERE v_latest_start_minute >= v_start_minute
  ),
  labeled AS (
    SELECT
      minute_of_day,
      (minute_of_day / 60)::int AS h24,
      (minute_of_day % 60)::int AS m
    FROM candidates
  ),
  stamped AS (
    SELECT
      (p_booking_date::timestamp
        + (h24 * interval '1 hour')
        + (m  * interval '1 minute')) AS ts,
      h24, m
    FROM labeled
  ),
  formatted AS (
    SELECT
      to_char(ts, 'FMHH12:MI AM') AS time_12h,
      to_char(ts, 'HH24:MI')      AS time_24h,
      h24, m
    FROM stamped
  ),
  slots AS (
    SELECT
      f.time_12h,
      f.time_24h,
      v_same_day_cutoff           AS same_day_cutoff,
      v_travel_buffer             AS travel_buffer,
      v_work_day_start            AS work_day_start,
      v_work_day_end              AS work_day_end,
      v_slot_interval_minutes     AS slot_interval_minutes,
      v_duration                  AS duration_hours,
      v_disable_same_day_booking  AS disable_same_day_booking,
      false                       AS is_meta_row,
      (f.h24 * 60 + f.m)          AS sort_key
    FROM formatted f
    WHERE
      NOT v_disable_same_day_booking
      AND public.validate_booking_timeslot_24h(
        f.time_24h,
        v_duration,
        p_booking_date,
        p_timezone
      ) = true
  ),
  unioned AS (
    SELECT
      s.time_12h,
      s.time_24h,
      s.same_day_cutoff,
      s.travel_buffer,
      s.work_day_start,
      s.work_day_end,
      s.slot_interval_minutes,
      s.duration_hours,
      s.disable_same_day_booking,
      s.is_meta_row,
      s.sort_key
    FROM slots s

    UNION ALL

    -- Meta-only row if no slots are returned (still provides settings + disable flag)
    SELECT
      NULL::text AS time_12h,
      NULL::text AS time_24h,
      v_same_day_cutoff,
      v_travel_buffer,
      v_work_day_start,
      v_work_day_end,
      v_slot_interval_minutes,
      v_duration,
      v_disable_same_day_booking,
      true AS is_meta_row,
      NULL::int AS sort_key
    WHERE NOT EXISTS (SELECT 1 FROM slots)
  )
  SELECT
    u.time_12h,
    u.time_24h,
    u.same_day_cutoff,
    u.travel_buffer,
    u.work_day_start,
    u.work_day_end,
    u.slot_interval_minutes,
    u.duration_hours,
    u.disable_same_day_booking,
    u.is_meta_row
  FROM unioned u
  ORDER BY u.sort_key NULLS LAST;

END;
$$;


ALTER FUNCTION "public"."get_available_timeslots_old"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_best_available_cleaners"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[], "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("cleaner_id" "uuid", "cleaner_name" "text", "avatar_url" "text", "bio" "text", "hourly_rate" numeric, "rating" double precision, "distance_meters" double precision, "final_score" double precision)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_cust_id uuid := auth.uid();
  v_booking_range tstzrange;
  v_cust_loc geography := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
BEGIN
  IF v_cust_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_booking_range := tstzrange(
    (p_date + p_time)::timestamptz,
    (p_date + p_time + (p_duration || ' hours')::interval)::timestamptz,
    '[)'
  );

  RETURN QUERY
  WITH available_cleaners AS (
    SELECT
      cd.user_id AS cleaner_user_id,
      p.fullname AS cleaner_fullname,
      p.avatar_url AS profile_avatar_url,
      COALESCE(cd.bio, p.bio) AS profile_bio,
      cd.hourly_rate AS cleaner_hourly_rate,
      cd.rating AS cleaner_rating,
      cd.skills AS cleaner_skills,
      cd.specialties AS cleaner_specialties,
      COALESCE(cd.base_location::geography, p.location_wkt) AS effective_location,
      ST_Distance(
        COALESCE(cd.base_location::geography, p.location_wkt),
        v_cust_loc
      )::float AS dist
    FROM public.cleaner_data cd
    JOIN public.profiles p ON p.user_id = cd.user_id
    WHERE cd.status = 'active'
      AND cd.verified = true
      AND COALESCE(cd.base_location::geography, p.location_wkt) IS NOT NULL
      AND (
        auth.uid() = cd.user_id
        OR public.is_profile_discoverable_by_others(p)
      )
      AND ST_DWithin(
        COALESCE(cd.base_location::geography, p.location_wkt),
        v_cust_loc,
        LEAST(
          COALESCE(cd.max_travel_distance_meters, p_max_distance_meters),
          p_max_distance_meters
        )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.bookings b
        WHERE b.cleaner_id = cd.user_id
          AND b.booking_period && v_booking_range
          AND b.status != 'cancelled'
          AND (
            p_exclude_booking_id IS NULL
            OR b.id <> p_exclude_booking_id
          )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.cleaner_availability_exceptions cae
        WHERE cae.cleaner_id = cd.user_id
          AND cae.exception_date = p_date
      )
  ),
  scored_cleaners AS (
    SELECT
      ac.cleaner_user_id,
      ac.cleaner_fullname,
      ac.profile_avatar_url,
      ac.profile_bio,
      ac.cleaner_hourly_rate,
      ac.cleaner_rating,
      ac.cleaner_skills,
      ac.cleaner_specialties,
      ac.dist,
      CASE
        WHEN cardinality(COALESCE(p_requested_services, ARRAY[]::text[])) > 0
        THEN (
          SELECT count(*)::float / cardinality(p_requested_services)
          FROM unnest(p_requested_services) s
          WHERE s = ANY(COALESCE(ac.cleaner_skills, ARRAY[]::text[]))
             OR s = ANY(COALESCE(ac.cleaner_specialties, ARRAY[]::text[]))
        ) * 40
        ELSE 20
      END AS s_score
    FROM available_cleaners ac
  )
  SELECT
    sc.cleaner_user_id AS cleaner_id,
    sc.cleaner_fullname AS cleaner_name,
    sc.profile_avatar_url AS avatar_url,
    sc.profile_bio AS bio,
    sc.cleaner_hourly_rate AS hourly_rate,
    sc.cleaner_rating::float AS rating,
    sc.dist::float AS distance_meters,
    (
      (GREATEST(0, (1.0 - (sc.dist / p_max_distance_meters))) * 30)
      + (COALESCE(sc.cleaner_rating, 0) / 5.0 * 30)
      + sc.s_score
    )::float AS final_score
  FROM scored_cleaners sc
  ORDER BY final_score DESC, sc.dist ASC;
END;
$$;


ALTER FUNCTION "public"."get_best_available_cleaners"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[], "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_best_available_cleaners_old"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[]) RETURNS TABLE("cleaner_id" "uuid", "cleaner_name" "text", "avatar_url" "text", "bio" "text", "hourly_rate" numeric, "rating" double precision, "distance_meters" double precision, "final_score" double precision)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_cust_id uuid := auth.uid();
  v_booking_range tstzrange;
  v_cust_loc geography := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
BEGIN
  IF v_cust_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_booking_range := tstzrange(
    (p_date + p_time)::timestamptz,
    (p_date + p_time + (p_duration || ' hours')::interval)::timestamptz,
    '[)'
  );

  RETURN QUERY
  WITH available_cleaners AS (
    SELECT
      cd.user_id AS cleaner_user_id,
      p.fullname AS cleaner_fullname,
      p.avatar_url AS profile_avatar_url,
      COALESCE(cd.bio, p.bio) AS profile_bio,
      cd.hourly_rate AS cleaner_hourly_rate,
      cd.rating AS cleaner_rating,
      cd.skills AS cleaner_skills,
      cd.specialties AS cleaner_specialties,
      COALESCE(cd.base_location::geography, p.location_wkt) AS effective_location,
      ST_Distance(
        COALESCE(cd.base_location::geography, p.location_wkt),
        v_cust_loc
      )::float AS dist
    FROM public.cleaner_data cd
    JOIN public.profiles p ON p.user_id = cd.user_id
    WHERE cd.status = 'active'
      AND cd.verified = true
      AND COALESCE(cd.base_location::geography, p.location_wkt) IS NOT NULL
      AND (
        auth.uid() = cd.user_id
        OR public.is_profile_discoverable_by_others(p)
      )
      AND ST_DWithin(
        COALESCE(cd.base_location::geography, p.location_wkt),
        v_cust_loc,
        LEAST(
          COALESCE(cd.max_travel_distance_meters, p_max_distance_meters),
          p_max_distance_meters
        )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.bookings b
        WHERE b.cleaner_id = cd.user_id
          AND b.booking_period && v_booking_range
          AND b.status != 'cancelled'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.cleaner_availability_exceptions cae
        WHERE cae.cleaner_id = cd.user_id
          AND cae.exception_date = p_date
      )
  ),
  scored_cleaners AS (
    SELECT
      ac.cleaner_user_id,
      ac.cleaner_fullname,
      ac.profile_avatar_url,
      ac.profile_bio,
      ac.cleaner_hourly_rate,
      ac.cleaner_rating,
      ac.cleaner_skills,
      ac.cleaner_specialties,
      ac.dist,
      CASE
        WHEN cardinality(COALESCE(p_requested_services, ARRAY[]::text[])) > 0
        THEN (
          SELECT count(*)::float / cardinality(p_requested_services)
          FROM unnest(p_requested_services) s
          WHERE s = ANY(COALESCE(ac.cleaner_skills, ARRAY[]::text[]))
             OR s = ANY(COALESCE(ac.cleaner_specialties, ARRAY[]::text[]))
        ) * 40
        ELSE 20
      END AS s_score
    FROM available_cleaners ac
  )
  SELECT
    sc.cleaner_user_id AS cleaner_id,
    sc.cleaner_fullname AS cleaner_name,
    sc.profile_avatar_url AS avatar_url,
    sc.profile_bio AS bio,
    sc.cleaner_hourly_rate AS hourly_rate,
    sc.cleaner_rating::float AS rating,
    sc.dist::float AS distance_meters,
    (
      (GREATEST(0, (1.0 - (sc.dist / p_max_distance_meters))) * 30)
      + (COALESCE(sc.cleaner_rating, 0) / 5.0 * 30)
      + sc.s_score
    )::float AS final_score
  FROM scored_cleaners sc
  ORDER BY final_score DESC, sc.dist ASC;
END;
$$;


ALTER FUNCTION "public"."get_best_available_cleaners_old"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_availability_by_id"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text" DEFAULT 'UTC'::"text", "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "fullname" "text", "avatar_url" "text", "hourly_rate" numeric, "is_available" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_start_local timestamp;
  v_end_local timestamp;
  v_requested_range tstzrange;
BEGIN
  v_start_local := (p_date + p_time)::timestamp;
  v_end_local := v_start_local + (p_duration * interval '1 hour') + interval '1 hour';

  v_requested_range := tstzrange(
    (v_start_local AT TIME ZONE p_timezone),
    (v_end_local AT TIME ZONE p_timezone),
    '[)'
  );

  RETURN QUERY
  SELECT
    cd.user_id,
    p.fullname,
    p.avatar_url,
    cd.hourly_rate,
    NOT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.cleaner_id = p_cleaner_id
        AND b.booking_period && v_requested_range
        AND b.status IS DISTINCT FROM 'cancelled'
        AND (
          p_exclude_booking_id IS NULL
          OR b.id <> p_exclude_booking_id
        )
    ) AS is_available
  FROM public.cleaner_data cd
  JOIN public.profiles p ON p.id = cd.user_id
  WHERE cd.user_id = p_cleaner_id
    AND cd.status = 'active';
END;
$$;


ALTER FUNCTION "public"."get_cleaner_availability_by_id"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text", "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_availability_by_id_old"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text" DEFAULT 'UTC'::"text") RETURNS TABLE("id" "uuid", "fullname" "text", "avatar_url" "text", "hourly_rate" numeric, "is_available" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_start_local timestamp;
    v_end_local   timestamp;
    v_requested_range tstzrange;
BEGIN
    -- Interpret p_date + p_time in the given timezone, then convert
    v_start_local := (p_date + p_time)::timestamp;
    v_end_local   := v_start_local + (p_duration * interval '1 hour') + interval '1 hour';

    v_requested_range := tstzrange(
        (v_start_local AT TIME ZONE p_timezone),
        (v_end_local   AT TIME ZONE p_timezone),
        '[)'
    );

    RETURN QUERY
    SELECT
        cd.user_id,
        p.fullname,
        p.avatar_url,
        cd.hourly_rate,
        NOT EXISTS (
            SELECT 1
            FROM public.bookings b
            WHERE b.cleaner_id = p_cleaner_id
              AND b.booking_period && v_requested_range
              AND b.status IS DISTINCT FROM 'cancelled'
        ) AS is_available
    FROM public.cleaner_data cd
    JOIN public.profiles p ON p.id = cd.user_id
    WHERE cd.user_id = p_cleaner_id
      AND cd.status = 'active';
END;
$$;


ALTER FUNCTION "public"."get_cleaner_availability_by_id_old"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_profile_v1"("target_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  result jsonb;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles p
  WHERE p.id = target_user_id
     OR p.user_id = target_user_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'profile', NULL,
      'cleaner_data', NULL,
      'verification', NULL
    );
  END IF;

  IF auth.uid() IS DISTINCT FROM v_profile.id
     AND auth.uid() IS DISTINCT FROM v_profile.user_id
     AND NOT public.is_profile_discoverable_by_others(v_profile) THEN
    RETURN jsonb_build_object(
      'profile', NULL,
      'cleaner_data', NULL,
      'verification', NULL
    );
  END IF;

  SELECT jsonb_build_object(
    'profile', (SELECT to_jsonb(p) FROM profiles p WHERE p.id = target_user_id OR p.user_id = target_user_id LIMIT 1),
    'cleaner_data', (SELECT to_jsonb(cd) FROM cleaner_data cd WHERE cd.user_id = target_user_id),
    'verification', (
      SELECT jsonb_build_object(
        'id_front_url', cv.id_front_url,
        'id_back_url', cv.id_back_url
      )
      FROM cleaner_verifications cv
      WHERE cv.id = target_user_id
    )
  )
  INTO result;

  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_cleaner_profile_v1"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_profile_with_reviews_and_stats"("p_user_id" "uuid") RETURNS TABLE("cleaner_data" "jsonb", "reviews_data" "jsonb", "jobs_completed" bigint, "repeat_customer_percent" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_cleaner RECORD;
  v_review_count INT;
  v_jobs_completed BIGINT;
  v_repeat_pct INT;
  v_reviews_json JSONB;
BEGIN
  -- Get cleaner_data + user + profile (use user_profiles; if your schema uses "profiles", replace user_profiles with profiles)
  SELECT
    cd.user_id,
    cd.hourly_rate,
    cd.rating,
    cd.verified,
    cd.service_areas,
    cd.skills,
    cd.years_experience,
    cd.certifications,
    cd.languages,
    u.email,
    u.phone,
    u.created_at AS user_created_at,
    COALESCE(up.fullname, TRIM(CONCAT(COALESCE(up.firstname, ''), ' ', COALESCE(up.lastname, ''))), 'Unknown') AS fullname,
    up.avatar_url,
    up.bio
  INTO v_cleaner
  FROM cleaner_data cd
  JOIN users u ON u.id = cd.user_id
  LEFT JOIN profiles up ON up.id = cd.user_id
  WHERE cd.user_id = p_user_id
    AND cd.status = 'active';

  IF NOT FOUND THEN
    RETURN;  -- 0 rows
  END IF;

  -- Review count for total_reviews
  SELECT COUNT(*)::INT INTO v_review_count
  FROM reviews
  WHERE reviewee_id = p_user_id;

  -- Reviews array with reviewer name (from user_profiles)
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'customer_name', COALESCE(rev_fullname.fullname, TRIM(CONCAT(COALESCE(rev_fullname.firstname, ''), ' ', COALESCE(rev_fullname.lastname, ''))), 'Anonymous'),
        'rating', r.rating,
        'comment', r.comment,
        'created_at', r.created_at
      ) ORDER BY r.created_at DESC
    ),
    '[]'::jsonb
  ) INTO v_reviews_json
  FROM reviews r
  LEFT JOIN profiles rev_fullname ON rev_fullname.id = r.reviewer_id
  WHERE r.reviewee_id = p_user_id;

  -- Jobs completed and repeat customer % (one review per booking: % of unique customers who booked more than once)
  WITH completed AS (
    SELECT customer_id
    FROM bookings
    WHERE cleaner_id = p_user_id AND status = 'completed'
  ),
  by_cust AS (
    SELECT customer_id, COUNT(*) AS n
    FROM completed
    GROUP BY customer_id
  )
  SELECT
    (SELECT COUNT(*) FROM completed)::BIGINT,
    CASE
      WHEN (SELECT COUNT(*) FROM by_cust) = 0 THEN NULL
      ELSE ROUND(
        100.0 * (SELECT COUNT(*) FROM by_cust WHERE n > 1) / (SELECT COUNT(*) FROM by_cust)
      )::INT
    END
  INTO v_jobs_completed, v_repeat_pct;

  -- Build cleaner JSON (match CleanerProfile shape)
  cleaner_data := jsonb_build_object(
    'id', v_cleaner.user_id,
    'name', v_cleaner.fullname,
    'email', COALESCE(v_cleaner.email, ''),
    'phone', v_cleaner.phone,
    'profile_image', v_cleaner.avatar_url,
    'bio', v_cleaner.bio,
    'skills', COALESCE(v_cleaner.skills, '{}'),
    'service_areas', COALESCE(v_cleaner.service_areas, '{}'),
    'hourly_rate', COALESCE(v_cleaner.hourly_rate, 0),
    'rating', COALESCE(v_cleaner.rating, 0),
    'total_reviews', v_review_count,
    'years_experience', COALESCE(v_cleaner.years_experience, 0),
    'is_verified', COALESCE(v_cleaner.verified, false),
    'certifications', COALESCE(v_cleaner.certifications, '{}'),
    'languages', COALESCE(v_cleaner.languages, '{}'),
    'created_at', v_cleaner.user_created_at
  );

  reviews_data := v_reviews_json;
  jobs_completed := v_jobs_completed;
  repeat_customer_percent := v_repeat_pct;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."get_cleaner_profile_with_reviews_and_stats"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_transaction_history"("p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone, "amount_subunit" integer, "type" "text", "description" "text", "status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        wt.id, 
        wt.created_at, 
        wt.amount_subunit, 
        wt.type, 
        wt.description,
        'completed'::TEXT -- Wallet transactions are usually already completed
    FROM public.wallet_transactions wt
    JOIN public.wallets w ON wt.wallet_id = w.id
    WHERE w.user_id = auth.uid()
    AND wt.created_at BETWEEN p_start_date AND p_end_date -- FILTERING LOGIC
    ORDER BY wt.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_cleaner_transaction_history"("p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaner_wallet"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_in_transit numeric;
    v_estimated numeric;
    v_total numeric;
BEGIN
    -- 1. Pending transfers or deposits
    SELECT COALESCE(SUM(amount), 0) INTO v_in_transit 
    FROM transactions WHERE user_id = p_user_id AND status = 'pending';

    -- 2. Available balance ready for payout
    SELECT COALESCE(SUM(amount), 0) INTO v_estimated 
    FROM transactions WHERE user_id = p_user_id AND status = 'available';

    -- 3. Historical total earned
    SELECT COALESCE(SUM(amount), 0) INTO v_total 
    FROM transactions WHERE user_id = p_user_id AND type = 'job_payment' AND status = 'success';

    RETURN json_build_object(
        'inTransit', v_in_transit,
        'estimatedPayout', v_estimated,
        'total', v_total
    );
END;
$$;


ALTER FUNCTION "public"."get_cleaner_wallet"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cleaners_with_score"("customer_id" "uuid", "requested_services" "text"[] DEFAULT '{}'::"text"[]) RETURNS TABLE("cleaner_id" "uuid", "cleaner_name" "text", "avatar_url" "text", "bio" "text", "hourly_rate" numeric, "rating" numeric, "years_experience" numeric, "distance_km" double precision, "match_score" double precision, "skills" "text"[], "specialties" "text"[], "metric_distance_score" double precision, "metric_skill_score" double precision)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE 
    customer_loc geography;
BEGIN 
    -- Get customer location from profiles
    SELECT location_wkt INTO customer_loc FROM public.profiles WHERE id = customer_id;

    RETURN QUERY
    WITH cleaner_base AS (
        SELECT 
            p.id as cid,
            p.fullname,
            p.avatar_url as a_url, -- From profiles
            p.bio as c_bio,
            cd.hourly_rate as hr,
            cd.rating as rt,
            cd.years_experience as yexp,
            cd.skills as sk,
            cd.specialties as sp,
            ST_Distance(p.location_wkt, customer_loc) / 1000.0 as dist
        FROM public.cleaner_data cd
        JOIN public.profiles p ON p.id = cd.user_id
        WHERE cd.status = 'active'
    ),
    scored_cleaners AS (
        SELECT 
            *,
            GREATEST(0, (1.0 - (dist / 30.0))) * 30 as d_score,
            (rt / 5.0) * 30 as r_score,
            CASE 
                WHEN array_length(requested_services, 1) > 0 
                THEN (
                    SELECT count(*)::float / array_length(requested_services, 1) 
                    FROM unnest(requested_services) s 
                    WHERE s = ANY(sk) OR s = ANY(sp)
                ) * 40
                ELSE 20 
            END as s_score
        FROM cleaner_base
    )
    SELECT 
        cid,
        fullname,
        a_url,
        c_bio,
        hr,
        rt,
        yexp,
        dist,
        (d_score + r_score + s_score) as final_score,
        sk,
        sp,
        d_score,
        s_score
    FROM scored_cleaners
    ORDER BY final_score DESC;
END;$$;


ALTER FUNCTION "public"."get_cleaners_with_score"("customer_id" "uuid", "requested_services" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_location_current_time"("p_timezone" "text", "p_duration_hours" numeric) RETURNS TABLE("current_timestamp_tz" timestamp with time zone, "local_date" "date", "local_time" time without time zone, "is_past_day_cutoff" boolean, "is_today_impossible" boolean, "latest_start_time" time without time zone, "same_day_cutoff_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_now_at_location timestamp;
  v_work_day_end numeric;
  v_travel_buffer numeric;
  v_latest_start_decimal numeric;
  v_current_time_decimal numeric;
  v_cutoff_time time;
  v_same_day_cutoff_at_local timestamp;
BEGIN
  -- Fetch settings
  SELECT value_numeric
  INTO v_work_day_end
  FROM booking_settings
  WHERE key = 'work_day_end';

  SELECT value_numeric
  INTO v_travel_buffer
  FROM booking_settings
  WHERE key = 'travel_buffer';

  -- Fallbacks
  v_work_day_end := COALESCE(v_work_day_end, 17.0);   -- 5 PM
  v_travel_buffer := COALESCE(v_travel_buffer, 1.0);  -- 1 hour

  -- Local wall clock time at the service location
  v_now_at_location := now() AT TIME ZONE p_timezone;

  -- Latest allowed start time today:
  -- work day end - service duration - travel buffer
  v_latest_start_decimal := v_work_day_end - p_duration_hours - v_travel_buffer;

  -- Clamp to valid day range
  v_latest_start_decimal := GREATEST(0, LEAST(23.999722, v_latest_start_decimal));

  -- Current local time as decimal hours
  v_current_time_decimal :=
    EXTRACT(HOUR FROM v_now_at_location)
    + (EXTRACT(MINUTE FROM v_now_at_location) / 60.0)
    + (EXTRACT(SECOND FROM v_now_at_location) / 3600.0);

  -- Convert latest start decimal to time
  v_cutoff_time := make_time(
    floor(v_latest_start_decimal)::int,
    floor((v_latest_start_decimal - floor(v_latest_start_decimal)) * 60)::int,
    0
  );

  -- Local timestamp for today's cutoff
  v_same_day_cutoff_at_local := date_trunc('day', v_now_at_location) + v_cutoff_time;

  RETURN QUERY
  SELECT
    now() AS current_timestamp_tz,
    v_now_at_location::date AS local_date,
    v_now_at_location::time AS local_time,
    (v_now_at_location >= v_same_day_cutoff_at_local) AS is_past_day_cutoff,
    (v_current_time_decimal > v_latest_start_decimal) AS is_today_impossible,
    v_cutoff_time AS latest_start_time,
    (v_same_day_cutoff_at_local AT TIME ZONE p_timezone) AS same_day_cutoff_at;
END;
$$;


ALTER FUNCTION "public"."get_location_current_time"("p_timezone" "text", "p_duration_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_wallet_balance"() RETURNS TABLE("balance" integer, "currency" character varying)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(w.balance_subunit, 0),
        COALESCE(w.currency, 'GHS')
    FROM public.wallets w
    WHERE w.user_id = auth.uid(); -- Automatically gets the ID of the logged-in user
END;
$$;


ALTER FUNCTION "public"."get_my_wallet_balance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_nearby_available_cleaners"("p_latitude" double precision, "p_longitude" double precision, "p_radius_meters" integer, "p_scheduled_date" "date", "p_start_time" time without time zone, "p_duration_hours" integer) RETURNS TABLE("id" "uuid", "fullname" "text", "avatar_url" "text", "distance_meters" double precision, "rating" double precision)
    LANGUAGE "sql" STABLE
    AS $$WITH
origin AS (
  SELECT ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography AS g
),
booking AS (
  SELECT tstzrange(
    (p_scheduled_date + p_start_time)::timestamptz,
    (p_scheduled_date + p_start_time + (p_duration_hours || ' hours')::interval)::timestamptz,
    '[)'
  ) AS r
),
cleaners AS (
  SELECT
    p.id,
    p.fullname,
    p.avatar_url,
    cd.rating,
    cd.max_travel_distance_meters,
    COALESCE(cd.base_location::geography, p.location_wkt) AS effective_location
  FROM public.profiles p
  JOIN public.cleaner_data cd
    ON cd.user_id = p.id
  WHERE COALESCE(cd.base_location::geography, p.location_wkt) IS NOT NULL
    AND cd.status = 'active'::public.cleaner_status
    AND cd.verified = true
    AND COALESCE(cd.is_online, false) = true
    AND EXISTS (
      SELECT 1
      FROM public.user_roles ur
      WHERE ur.user_id = p.id
        AND ur.role_id = 'cleaner'
    )
)
SELECT
  c.id,
  c.fullname,
  c.avatar_url,
  d.distance_meters,
  c.rating::double precision AS rating
FROM cleaners c
CROSS JOIN origin o
CROSS JOIN booking bk
CROSS JOIN LATERAL (
  SELECT ST_Distance(c.effective_location, o.g) AS distance_meters
) d
WHERE ST_DWithin(c.effective_location, o.g, p_radius_meters)
  AND d.distance_meters <= COALESCE(c.max_travel_distance_meters, 30000)
  AND NOT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.cleaner_id = c.id
      AND b.status <> 'cancelled'::public.booking_status
      AND b.booking_period && bk.r
  )
ORDER BY d.distance_meters ASC
LIMIT 200;$$;


ALTER FUNCTION "public"."get_nearby_available_cleaners"("p_latitude" double precision, "p_longitude" double precision, "p_radius_meters" integer, "p_scheduled_date" "date", "p_start_time" time without time zone, "p_duration_hours" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_own_cleaner_location"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_lat     double precision;
  v_lng     double precision;
  v_max     integer;
  v_geom    geometry;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT cd.base_location, cd.max_travel_distance_meters
    INTO v_geom, v_max
  FROM public.cleaner_data cd
  WHERE cd.user_id = v_user_id;

  IF v_geom IS NOT NULL THEN
    v_lat := ST_Y(v_geom);
    v_lng := ST_X(v_geom);
  END IF;

  RETURN jsonb_build_object(
    'has_location',                v_geom IS NOT NULL,
    'latitude',                    v_lat,
    'longitude',                   v_lng,
    'max_travel_distance_meters',  COALESCE(v_max, 30000)
  );
END;
$$;


ALTER FUNCTION "public"."get_own_cleaner_location"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_own_cleaner_location"() IS 'Authenticated user reads their own cleaner_data.base_location. Returns lat/lng as numbers so callers do not parse PostGIS WKB.';



CREATE OR REPLACE FUNCTION "public"."get_payment_split_config"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT jsonb_object_agg(key, value)
  FROM payment_split_config
  WHERE key IN ('tax_percentage', 'vendor_percentage');
$$;


ALTER FUNCTION "public"."get_payment_split_config"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_payout_system_logs"() RETURNS TABLE("id" bigint, "status_code" integer, "content" "text", "url" "text", "created_at" timestamp with time zone, "delivery_status" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'net'
    AS $$
  SELECT
    q.id,
    q.status_code,
    q.content,
    NULL::text AS url,
    NULL::timestamptz AS created_at,
    CASE
      WHEN q.timed_out THEN 'timeout'
      WHEN q.status_code >= 200 AND q.status_code < 300 THEN 'success'
      WHEN q.status_code >= 400 THEN 'failed'
      ELSE 'pending'
    END AS delivery_status
  FROM net._http_response q
  ORDER BY q.id DESC
  LIMIT 500;
$$;


ALTER FUNCTION "public"."get_payout_system_logs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_pending_booking_for_edit"("p_customer_id" "uuid", "p_booking_id" "uuid") RETURNS TABLE("id" "uuid", "customer_id" "uuid", "cleaner_id" "uuid", "service_id" integer, "title" "text", "scheduled_date" "date", "scheduled_time" time without time zone, "duration_hours" numeric, "address" "text", "special_instructions" "text", "status" "public"."booking_status", "payment_status" "text", "subscription_id" "uuid", "home_size" "text", "extra_task_ids" "text"[], "duration_adjustment" numeric, "duration_computed" numeric, "duration_final" numeric, "timezone_name" "text", "cleaner_assigned_at" timestamp with time zone, "service_duration_option_id" "uuid", "location_latitude" double precision, "location_longitude" double precision, "service" "jsonb")
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  SELECT
    b.id,
    b.customer_id,
    b.cleaner_id,
    b.service_id,
    b.title,
    b.scheduled_date,
    b.scheduled_time,
    b.duration_hours,
    b.address,
    b.special_instructions,
    b.status,
    b.payment_status,
    b.subscription_id,
    b.home_size,
    b.extra_task_ids,
    b.duration_adjustment,
    b.duration_computed,
    b.duration_final,
    b.timezone_name,
    b.cleaner_assigned_at,
    b.service_duration_option_id,
    CASE
      WHEN b.location_coordinates IS NOT NULL
        THEN ST_Y(b.location_coordinates::geometry)
      ELSE NULL
    END AS location_latitude,
    CASE
      WHEN b.location_coordinates IS NOT NULL
        THEN ST_X(b.location_coordinates::geometry)
      ELSE NULL
    END AS location_longitude,
    to_jsonb(s.*) AS service
  FROM public.bookings b
  JOIN public.service_types s
    ON s.id = b.service_id
  WHERE b.id = p_booking_id
    AND b.customer_id = p_customer_id
    AND b.status IN ('pending', 'confirmed', 'scheduled')
    AND b.subscription_id IS NULL
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_pending_booking_for_edit"("p_customer_id" "uuid", "p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_service_categories"() RETURNS TABLE("id" bigint, "name" "text", "icon" "text", "service_types" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    sc.id::bigint, -- FIX: Explicitly cast the ID to match the return table definition
    sc.name,
    sc.icon,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', st.id,
          'name', st.name,
          'price', st.price,
          'duration', st.duration
        )
      ) FILTER (WHERE st.id IS NOT NULL), 
      '[]'::jsonb
    ) as service_types
  FROM service_categories sc
  LEFT JOIN service_types st ON st.category_id = sc.id
  WHERE st.active = true OR st.id IS NULL
  GROUP BY sc.id, sc.name, sc.icon;
END;
$$;


ALTER FUNCTION "public"."get_service_categories"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timezone_from_coordinates"("latitude" numeric, "longitude" numeric) RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_timezone text;
BEGIN
    SELECT tzid INTO v_timezone
    FROM timezone_boundaries
    WHERE ST_Intersects(
        geom, 
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4386)
    )
    LIMIT 1;

    RETURN COALESCE(v_timezone, 'UTC');
END;
$$;


ALTER FUNCTION "public"."get_timezone_from_coordinates"("latitude" numeric, "longitude" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean DEFAULT false) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile json;
  v_cleaner json;
  v_notifications json;
  v_roles json;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT json_build_object(
    'fullname', fullname,
    'firstname', firstname,
    'lastname', lastname,
    'avatar_url', avatar_url,
    'bio', bio,
    'address', address,
    'deactivated_at', deactivated_at,
    'deletion_status', deletion_status,
    'deletion_requested_at', deletion_requested_at,
    'deletion_scheduled_for', deletion_scheduled_for,
    'deletion_started_at', deletion_started_at,
    'deletion_completed_at', deletion_completed_at
  )
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  SELECT json_build_object(
    'rating', rating,
    'completed_jobs', completed_jobs,
    'hourly_rate', hourly_rate,
    'verified', verified
  )
  INTO v_cleaner
  FROM public.cleaner_data
  WHERE user_id = p_user_id;

  SELECT json_agg(role_id) INTO v_roles
  FROM public.user_roles
  WHERE user_id = p_user_id;

  SELECT json_agg(t) INTO v_notifications
  FROM (
    SELECT id, type, message, created_at
    FROM public.notifications
    WHERE user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 5
  ) t;

  RETURN json_build_object(
    'profile', COALESCE(v_profile, '{}'::json),
    'profile_exists', v_profile IS NOT NULL,
    'cleaner', v_cleaner,
    'roles', COALESCE(v_roles, '[]'::json),
    'notifications', COALESCE(v_notifications, '[]'::json)
  );
END;
$$;


ALTER FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) IS 'Owner-only session/dashboard payload (profile lifecycle, roles, notifications). Unauthorized if auth.uid() <> p_user_id. Not for public profile lookup; add get_public_user_profile_data for listings/cards if needed.';



CREATE OR REPLACE FUNCTION "public"."get_user_profile_stats"("p_user_id" "uuid", "p_is_cleaner" boolean DEFAULT false) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_result json;
  v_cleaner_rating numeric;
BEGIN
  IF p_is_cleaner THEN
    SELECT rating INTO v_cleaner_rating
    FROM cleaner_data WHERE user_id = p_user_id;

    SELECT json_build_object(
      'earnedToday', COALESCE((
        SELECT SUM(COALESCE(final_amount_minor, total_price))::numeric
        FROM bookings
        WHERE cleaner_id = p_user_id
          AND status = 'completed'
          AND (created_at AT TIME ZONE 'UTC')::date = (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date
      ), 0),
      'totalTrips', COALESCE((
        SELECT COUNT(*)::integer FROM bookings WHERE cleaner_id = p_user_id
      ), 0),
      'completedJobs', COALESCE((
        SELECT COUNT(*)::integer FROM bookings
        WHERE cleaner_id = p_user_id AND status = 'completed'
      ), 0),
      'averageRating', COALESCE((
        SELECT ROUND(AVG(rating)::numeric, 1)
        FROM reviews WHERE reviewee_id = p_user_id
      ), COALESCE(v_cleaner_rating, 0)),
      'reviewCount', COALESCE((
        SELECT COUNT(*)::integer FROM reviews WHERE reviewee_id = p_user_id
      ), 0)
    ) INTO v_result;
  ELSE
    SELECT json_build_object(
      'totalBookings', COALESCE((
        SELECT COUNT(*)::integer FROM bookings WHERE customer_id = p_user_id
      ), 0),
      'activeBookings', COALESCE((
        SELECT COUNT(*)::integer FROM bookings
        WHERE customer_id = p_user_id
          AND status IN ('pending', 'scheduled', 'in_progress')
      ), 0),
      'completedBookings', COALESCE((
        SELECT COUNT(*)::integer FROM bookings
        WHERE customer_id = p_user_id AND status = 'completed'
      ), 0),
      'totalSpent', COALESCE((
        SELECT SUM(COALESCE(final_amount_minor, total_price))::numeric
        FROM bookings
        WHERE customer_id = p_user_id AND status = 'completed'
      ), 0),
      'averageRating', COALESCE((
        SELECT ROUND(AVG(rating)::numeric, 1)
        FROM reviews WHERE reviewer_id = p_user_id
      ), 0),
      'reviewCount', COALESCE((
        SELECT COUNT(*)::integer FROM reviews WHERE reviewer_id = p_user_id
      ), 0)
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_user_profile_stats"("p_user_id" "uuid", "p_is_cleaner" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_profile json;
    v_cleaner json;
    v_roles text[];
BEGIN
    -- 1. Fetch Profile Data
    SELECT json_build_object(
        'fullname', fullname, 
        'avatar_url', avatar_url
    ) INTO v_profile 
    FROM public.profiles 
    WHERE id = p_user_id;

    -- 2. Fetch Cleaner Data (if it exists)
    SELECT json_build_object(
        'verified', verified, 
        'rating', rating
    ) INTO v_cleaner 
    FROM public.cleaner_data 
    WHERE user_id = p_user_id;

    -- 3. Fetch All Roles for this user
    SELECT array_agg(role_id) INTO v_roles
    FROM public.user_roles
    WHERE user_id = p_user_id;

    -- Return everything as a single JSON object
    RETURN json_build_object(
        'profile', v_profile,
        'cleaner', v_cleaner,
        'roles', COALESCE(v_roles, '{}'::text[])
    );
END;
$$;


ALTER FUNCTION "public"."get_user_role"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_booking_payment_status_writes"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Service-role calls (Paystack webhook, admin scripts) bypass entirely.
  if auth.role() = 'service_role' then
    return new;
  end if;

  -- Non-service-role callers cannot transition payment_status to a privileged value.
  if new.payment_status is distinct from old.payment_status
     and new.payment_status in ('paid', 'refunded') then
    raise exception
      'payment_status transitions to % are server-only (use the Paystack webhook)',
      new.payment_status
      using errcode = '42501'; -- insufficient_privilege
  end if;

  -- Once a booking is paid, the column is locked for non-service-role callers.
  -- This prevents a customer from "unpaying" their own booking by writing
  -- `payment_status = 'failed'` after the webhook has confirmed the charge.
  if old.payment_status = 'paid'
     and new.payment_status is distinct from old.payment_status then
    raise exception
      'cannot change payment_status of a paid booking from client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."guard_booking_payment_status_writes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_job_completion"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- When booking is marked 'completed', move associated transaction to 'available'
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    UPDATE public.transactions
    SET status = 'available',
        updated_at = now()
    WHERE booking_id = NEW.id 
    AND type = 'job_payment';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_job_completion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_google_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- 1. Insert into public.users first (profiles.id references users.id)
  INSERT INTO public.users (id, email, password_hash)
  VALUES (NEW.id, NEW.email, '')
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert into public.profiles (include user_id for NOT NULL constraint)
  INSERT INTO public.profiles (id, user_id, firstname, lastname, fullname, avatar_url)
  VALUES (
    NEW.id,
    NEW.id,
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO UPDATE SET
    avatar_url = EXCLUDED.avatar_url,
    fullname = EXCLUDED.fullname;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_google_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_multi_role"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_phone text;
BEGIN
  v_phone := public.normalize_phone_for_users(
    COALESCE(
      NEW.phone,
      NEW.raw_user_meta_data->>'phone',
      NEW.raw_user_meta_data->>'phone_number'
    )
  );

  INSERT INTO public.users (id, email, phone)
  VALUES (
    NEW.id,
    lower(NULLIF(btrim(NEW.email), '')),
    CASE
      WHEN v_phone IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.users u
         WHERE u.phone = v_phone
           AND u.id <> NEW.id
       )
      THEN v_phone
      ELSE NULL
    END
  )
  ON CONFLICT (id) DO UPDATE
  SET
    email = COALESCE(EXCLUDED.email, public.users.email),
    phone = CASE
      WHEN v_phone IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.users u
         WHERE u.phone = v_phone
           AND u.id <> public.users.id
       )
      THEN v_phone
      ELSE public.users.phone
    END;

  INSERT INTO public.profiles (id, user_id, firstname, lastname)
  VALUES (
    NEW.id,
    NEW.id,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'first_name', ''),
      NULLIF(split_part(trim(NEW.raw_user_meta_data->>'name'), ' ', 1), '')
    ),
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'last_name', ''),
      NULLIF(
        trim(
          substr(
            trim(NEW.raw_user_meta_data->>'name'),
            length(split_part(trim(NEW.raw_user_meta_data->>'name'), ' ', 1)) + 2
          )
        ),
        ''
      )
    )
  )
  ON CONFLICT (id) DO UPDATE
  SET
    firstname = COALESCE(EXCLUDED.firstname, public.profiles.firstname),
    lastname  = COALESCE(EXCLUDED.lastname, public.profiles.lastname);

  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (NEW.id, COALESCE(NEW.raw_app_meta_data->>'role', 'customer'))
  ON CONFLICT (user_id, role_id) DO NOTHING;

  IF COALESCE(NEW.raw_app_meta_data->>'role', '') = 'cleaner' THEN
    INSERT INTO public.cleaner_data (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user_multi_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("_role" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role_id = _role);
$$;


ALTER FUNCTION "public"."has_role"("_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_invite_code_usage"("p_code" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
declare
  updated_rows int;
begin
  update invite_codes
  set uses = uses + 1,
      updated_at = now()
  where code = p_code
    and enabled = true
    and (expires_at is null or expires_at > now())
    and uses < max_uses;

  get diagnostics updated_rows = row_count;
  return updated_rows = 1;
end;
$$;


ALTER FUNCTION "public"."increment_invite_code_usage"("p_code" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."psk_transaction" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "reference" "text" NOT NULL,
    "paystack_id" bigint,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "fee_amount" numeric(10,2) NOT NULL,
    "total_captured" numeric(10,2) NOT NULL,
    "currency" "text" DEFAULT 'GHS'::"text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "customer_id" "uuid"
);


ALTER TABLE "public"."psk_transaction" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insert_psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") RETURNS "public"."psk_transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_new_transaction public.psk_transaction;
BEGIN
    INSERT INTO public.psk_transaction (
        booking_id,
        user_id,
        reference,
        paystack_id,
        amount,
        fee_amount,
        total_captured,
        currency,
        metadata
    )
    VALUES (
        p_booking_id,
        p_user_id,
        p_reference,
        p_paystack_id,
        p_amount,
        p_fee_amount,
        p_total_captured,
        p_currency,
        p_metadata
    )
    RETURNING * INTO v_new_transaction;

    RETURN v_new_transaction;
END;
$$;


ALTER FUNCTION "public"."insert_psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"("user_uuid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = user_uuid AND role_id = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_admin"("user_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT public.is_co_cleaner_invitee_eligible(p_user_id);
$$;


ALTER FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.cleaner_data AS cd
      WHERE cd.user_id = p_user_id
        AND cd.verified IS TRUE
    )
    OR EXISTS (
      SELECT 1
      FROM public.kyc_profiles AS kp
      WHERE kp.user_id = p_user_id
        AND (
          kp.review_answer = 'GREEN'
          OR kp.kyc_status IN ('completed', 'approved', 'verified')
        )
    );
$$;


ALTER FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.co_cleaner_relationships AS r
    WHERE r.co_cleaner_id = p_user_id
  );
$$;


ALTER FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_platform_fee_admin"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  has_role_col boolean;
BEGIN
  -- Primary: user_roles
  IF EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role_id = 'admin'
  ) THEN
    RETURN true;
  END IF;
  -- Fallback: users.role if column exists
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role'
  ) INTO has_role_col;
  IF has_role_col THEN
    RETURN (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin';
  END IF;
  RETURN false;
END;
$$;


ALTER FUNCTION "public"."is_platform_fee_admin"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "firstname" "text",
    "lastname" "text",
    "fullname" "text",
    "avatar_url" "text",
    "bio" "text",
    "address" "text",
    "location_wkt" "public"."geography"(Point,4326) DEFAULT "public"."st_geomfromtext"('POINT(-0.186964 5.650562)'::"text", 4326),
    "preferences" "jsonb" DEFAULT '{}'::"jsonb",
    "notification_settings" "jsonb" DEFAULT '{"app": true, "sms": true, "email": true}'::"jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "deleted_at" timestamp with time zone,
    "deactivated_at" timestamp with time zone,
    "deletion_requested_at" timestamp with time zone,
    "deletion_scheduled_for" timestamp with time zone,
    "deletion_started_at" timestamp with time zone,
    "deletion_completed_at" timestamp with time zone,
    "deletion_status" "text" DEFAULT 'none'::"text" NOT NULL,
    CONSTRAINT "profiles_deletion_status_check" CHECK (("deletion_status" = ANY (ARRAY['none'::"text", 'scheduled'::"text", 'cancelled'::"text", 'processing'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."deleted_at" IS 'When set, the customer account is soft-deleted: app signs the user out and hides the profile from others.';



COMMENT ON COLUMN "public"."profiles"."deactivated_at" IS 'When set, profile is deactivated (hidden from others per RLS + app rules). Distinct from permanent deletion lifecycle.';



COMMENT ON COLUMN "public"."profiles"."deletion_requested_at" IS 'When the user requested permanent account deletion.';



COMMENT ON COLUMN "public"."profiles"."deletion_scheduled_for" IS 'End of the cancellation grace period; trusted deletion job may start at or after this time.';



COMMENT ON COLUMN "public"."profiles"."deletion_started_at" IS 'When the anonymization/removal job began for this account.';



COMMENT ON COLUMN "public"."profiles"."deletion_completed_at" IS 'When active-system anonymization completed; backups may persist longer (~90 days).';



COMMENT ON COLUMN "public"."profiles"."deletion_status" IS 'Lifecycle: none | scheduled | cancelled | processing | completed.';



CREATE OR REPLACE FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    p.deleted_at IS NULL
    AND p.deactivated_at IS NULL
    AND COALESCE(p.deletion_status, 'none') NOT IN ('scheduled', 'processing', 'completed')
    AND COALESCE((p.preferences->>'profile_visibility')::boolean, true) IS TRUE;
$$;


ALTER FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") IS 'True when the profile may appear in cleaner search and public profile views (profile_visibility defaults on).';



CREATE OR REPLACE FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    viewer_id IS NOT NULL
    AND (
      viewer_id = p.id
      OR viewer_id = p.user_id
      OR public.is_profile_discoverable_by_others(p)
    );
$$;


ALTER FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") IS 'True when viewer_id is the profile owner or the profile is discoverable by others.';



CREATE OR REPLACE FUNCTION "public"."leave_co_cleaner_team"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_lead uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  DELETE FROM public.co_cleaner_relationships
  WHERE co_cleaner_id = v_uid
  RETURNING lead_cleaner_id INTO v_lead;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_on_team');
  END IF;

  RETURN jsonb_build_object('success', true, 'lead_cleaner_id', v_lead);
END;
$$;


ALTER FUNCTION "public"."leave_co_cleaner_team"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") RETURNS TABLE("email" "text", "has_account" boolean, "matched_by" "text", "phone_e164" "text", "providers" "text"[], "supports_email_password" boolean, "supports_phone_otp" boolean, "user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $_$
  WITH input AS (
    SELECT
      trim(lookup_identifier) AS raw_identifier,
      lower(trim(lookup_identifier)) AS normalized_email,
      public.phone_lookup_variants(trim(lookup_identifier)) AS phone_variants
  ),

  matched_auth_user AS (
    SELECT
      au.id,
      au.email,
      au.phone,
      au.encrypted_password,
      CASE
        WHEN i.raw_identifier LIKE '%@%'
          AND lower(au.email) = i.normalized_email
          THEN 'email'
        WHEN i.raw_identifier NOT LIKE '%@%'
          AND coalesce(au.phone, '') <> ''
          AND public.phone_lookup_variants(au.phone) && i.phone_variants
          THEN 'phone'
        ELSE NULL
      END AS matched_by
    FROM auth.users au
    CROSS JOIN input i
    WHERE
      (
        i.raw_identifier LIKE '%@%'
        AND lower(au.email) = i.normalized_email
      )
      OR
      (
        i.raw_identifier NOT LIKE '%@%'
        AND coalesce(au.phone, '') <> ''
        AND public.phone_lookup_variants(au.phone) && i.phone_variants
      )
    ORDER BY au.created_at DESC
    LIMIT 1
  ),

  matched_public_user AS (
    SELECT
      pu.id,
      pu.email,
      pu.phone,
      NULL::text AS encrypted_password,
      CASE
        WHEN i.raw_identifier LIKE '%@%'
          AND lower(pu.email) = i.normalized_email
          THEN 'email'
        WHEN i.raw_identifier NOT LIKE '%@%'
          AND coalesce(pu.phone, '') <> ''
          AND public.phone_lookup_variants(pu.phone) && i.phone_variants
          THEN 'phone'
        ELSE NULL
      END AS matched_by
    FROM public.users pu
    CROSS JOIN input i
    WHERE NOT EXISTS (SELECT 1 FROM matched_auth_user)
      AND (
        (
          i.raw_identifier LIKE '%@%'
          AND lower(pu.email) = i.normalized_email
        )
        OR
        (
          i.raw_identifier NOT LIKE '%@%'
          AND coalesce(pu.phone, '') <> ''
          AND public.phone_lookup_variants(pu.phone) && i.phone_variants
        )
      )
    ORDER BY pu.created_at DESC
    LIMIT 1
  ),

  matched_user AS (
    SELECT * FROM matched_auth_user
    UNION ALL
    SELECT * FROM matched_public_user
    LIMIT 1
  ),

  identity_providers AS (
    SELECT
      ai.user_id,
      array_agg(DISTINCT lower(ai.provider) ORDER BY lower(ai.provider)) AS providers
    FROM auth.identities ai
    WHERE ai.user_id IN (SELECT id FROM matched_user)
    GROUP BY ai.user_id
  ),

  canonical_phone AS (
    SELECT
      mu.id,
      coalesce(
        (
          SELECT v
          FROM unnest(public.phone_lookup_variants(mu.phone)) AS v
          WHERE v ~ '^\+[1-9][0-9]{6,14}$'
          ORDER BY length(v) DESC
          LIMIT 1
        ),
        NULLIF(btrim(mu.phone), '')
      ) AS phone_e164
    FROM matched_user mu
  )

  SELECT
    mu.email,
    true AS has_account,
    mu.matched_by,
    cp.phone_e164,
    coalesce(ip.providers, ARRAY[]::text[]) AS providers,
    (
      coalesce(mu.encrypted_password, '') <> ''
      OR 'email' = ANY (coalesce(ip.providers, ARRAY[]::text[]))
    ) AS supports_email_password,
    (
      coalesce(cp.phone_e164, '') <> ''
      OR 'phone' = ANY (coalesce(ip.providers, ARRAY[]::text[]))
    ) AS supports_phone_otp,
    mu.id AS user_id
  FROM matched_user mu
  LEFT JOIN identity_providers ip ON ip.user_id = mu.id
  LEFT JOIN canonical_phone cp ON cp.id = mu.id

  UNION ALL

  SELECT
    NULL::text,
    false,
    NULL::text,
    NULL::text,
    ARRAY[]::text[],
    false,
    false,
    NULL::uuid
  WHERE NOT EXISTS (SELECT 1 FROM matched_user)

  LIMIT 1;
$_$;


ALTER FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") IS 'Read-only sign-in lookup by email or phone (Ghana variant-aware). Matches mobile RPC contract.';



CREATE OR REPLACE FUNCTION "public"."manage_base_durations"("action" "text", "duration_id" "text" DEFAULT NULL::"text", "new_hours" numeric DEFAULT NULL::numeric) RETURNS TABLE("id" "text", "label" "text", "hours" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update logic
    IF action = 'update_hours' AND duration_id IS NOT NULL AND new_hours IS NOT NULL THEN
        UPDATE public.base_durations 
        SET hours = new_hours, updated_at = now()
        WHERE public.base_durations.id = duration_id;
    END IF;

    -- Return all rows
    RETURN QUERY SELECT d.id, d.label, d.hours FROM public.base_durations d ORDER BY d.hours ASC;
END;
$$;


ALTER FUNCTION "public"."manage_base_durations"("action" "text", "duration_id" "text", "new_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."manage_extra_tasks"("action" "text", "task_id" "text" DEFAULT NULL::"text", "new_hours" numeric DEFAULT NULL::numeric) RETURNS TABLE("id" "text", "label" "text", "hours" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update logic
    IF action = 'update_hours' AND task_id IS NOT NULL AND new_hours IS NOT NULL THEN
        UPDATE public.extra_tasks 
        SET hours = new_hours, updated_at = now()
        WHERE public.extra_tasks.id = task_id;
    END IF;

    -- Return all rows regardless of whether an update happened
    RETURN QUERY SELECT t.id, t.label, t.hours FROM public.extra_tasks t ORDER BY t.label ASC;
END;
$$;


ALTER FUNCTION "public"."manage_extra_tasks"("action" "text", "task_id" "text", "new_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.bookings%ROWTYPE;
  v_new_status public.booking_status;
  v_notif_type public.notification_type;
  v_title text;
  v_message text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_booking_id');
  END IF;

  IF p_milestone NOT IN ('en_route', 'arrived') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_milestone');
  END IF;

  IF p_milestone = 'en_route' THEN
    v_new_status := 'en_route';
    v_notif_type := 'cleaner_en_route';
    v_title := 'Cleaner on the way';
    v_message := 'Your cleaner is heading to your location.';
  ELSE
    v_new_status := 'arrived';
    v_notif_type := 'cleaner_arrived';
    v_title := 'Cleaner has arrived';
    v_message := 'Your cleaner has arrived at your location.';
  END IF;

  SELECT * INTO v_row
  FROM public.bookings
  WHERE id = p_booking_id
    AND cleaner_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  IF p_milestone = 'en_route' AND v_row.status NOT IN ('confirmed', 'scheduled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_transition');
  END IF;

  IF p_milestone = 'arrived' AND v_row.status <> 'en_route' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_transition');
  END IF;

  UPDATE public.bookings
  SET
    status = v_new_status,
    updated_at = now()
  WHERE id = p_booking_id;

  INSERT INTO public.booking_timeline (booking_id, stage, changed_at, notes)
  VALUES (p_booking_id, v_new_status, now(), NULL);

  IF v_row.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, message, data)
    VALUES (
      v_row.customer_id,
      v_notif_type,
      v_title,
      v_message,
      jsonb_build_object(
        'booking_id', p_booking_id,
        'milestone', p_milestone,
        'cleaner_id', v_uid
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'milestone', p_milestone,
    'customer_id', v_row.customer_id,
    'new_status', v_new_status::text
  );
END;
$$;


ALTER FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_primary public.users%ROWTYPE;
  v_secondary public.users%ROWTYPE;
  v_snapshot jsonb;
BEGIN
  IF p_primary IS NULL OR p_secondary IS NULL THEN
    RAISE EXCEPTION 'invalid_user_ids' USING ERRCODE = 'P0001';
  END IF;

  IF p_primary = p_secondary THEN
    RAISE EXCEPTION 'same_user' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_primary FROM public.users WHERE id = p_primary;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'primary_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_secondary FROM public.users WHERE id = p_secondary;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'secondary_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_secondary AND role_id IN ('admin', 'reviewer')
  ) THEN
    RAISE EXCEPTION 'secondary_is_privileged' USING ERRCODE = 'P0003';
  END IF;

  v_snapshot := jsonb_build_object(
    'primary', jsonb_build_object('id', v_primary.id, 'email', v_primary.email, 'phone', v_primary.phone),
    'secondary', jsonb_build_object('id', v_secondary.id, 'email', v_secondary.email, 'phone', v_secondary.phone)
  );

  -- Low collision risk: direct FK reassignments
  UPDATE public.bookings SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.bookings SET cleaner_id = p_primary WHERE cleaner_id = p_secondary;
  UPDATE public.notifications SET user_id = p_primary WHERE user_id = p_secondary;
  UPDATE public.subscriptions SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.subscriptions SET cleaner_id = p_primary WHERE cleaner_id = p_secondary;
  UPDATE public.reviews SET reviewer_id = p_primary WHERE reviewer_id = p_secondary;
  UPDATE public.reviews SET reviewee_id = p_primary WHERE reviewee_id = p_secondary;
  UPDATE public.user_login_sessions SET user_id = p_primary WHERE user_id = p_secondary;
  UPDATE public.cleaner_leads SET linked_user_id = p_primary WHERE linked_user_id = p_secondary;
  UPDATE public.feedback SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.feedback SET cleaner_id = p_primary WHERE cleaner_id = p_secondary;
  UPDATE public.jobs SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.jobs SET claimed_by = p_primary WHERE claimed_by = p_secondary;
  UPDATE public.conversations SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.conversations SET cleaner_id = p_primary WHERE cleaner_id = p_secondary;
  UPDATE public.psk_transaction SET customer_id = p_primary WHERE customer_id = p_secondary;
  UPDATE public.psk_transaction SET cleaner_id = p_primary WHERE cleaner_id = p_secondary;

  -- cleaner_applications: drop secondary rows that would duplicate primary phone/email
  DELETE FROM public.cleaner_applications a_s
  WHERE a_s.user_id = p_secondary
    AND (
      EXISTS (
        SELECT 1 FROM public.cleaner_applications a_p
        WHERE a_p.user_id = p_primary AND a_p.phone = a_s.phone
      )
      OR (
        a_s.email IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.cleaner_applications a_p
          WHERE a_p.user_id = p_primary
            AND a_p.email IS NOT NULL
            AND lower(trim(a_p.email)) = lower(trim(a_s.email))
        )
      )
    );
  UPDATE public.cleaner_applications SET user_id = p_primary WHERE user_id = p_secondary;

  -- kyc_profiles: drop secondary rows that would duplicate primary subject_type or sumsub applicant
  DELETE FROM public.kyc_profiles k_s
  WHERE k_s.user_id = p_secondary
    AND (
      EXISTS (
        SELECT 1 FROM public.kyc_profiles k_p
        WHERE k_p.user_id = p_primary AND k_p.subject_type = k_s.subject_type
      )
      OR (
        k_s.sumsub_applicant_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.kyc_profiles k_p
          WHERE k_p.user_id = p_primary
            AND k_p.sumsub_applicant_id = k_s.sumsub_applicant_id
        )
      )
    );
  UPDATE public.kyc_profiles SET user_id = p_primary WHERE user_id = p_secondary;

  -- device_tokens: drop secondary tokens already registered on primary, then reassign
  DELETE FROM public.device_tokens d_s
  WHERE d_s.user_id = p_secondary
    AND EXISTS (
      SELECT 1 FROM public.device_tokens d_p
      WHERE d_p.user_id = p_primary AND d_p.token = d_s.token
    );
  UPDATE public.device_tokens SET user_id = p_primary WHERE user_id = p_secondary;

  -- preferred_cleaners (user_id + cleaner_id): upsert merged pairs, remove secondary rows
  INSERT INTO public.preferred_cleaners (user_id, cleaner_id, created_at)
  SELECT
    CASE WHEN pc.user_id = p_secondary THEN p_primary ELSE pc.user_id END,
    CASE WHEN pc.cleaner_id = p_secondary THEN p_primary ELSE pc.cleaner_id END,
    pc.created_at
  FROM public.preferred_cleaners pc
  WHERE pc.user_id = p_secondary OR pc.cleaner_id = p_secondary
  ON CONFLICT (user_id, cleaner_id) DO NOTHING;

  DELETE FROM public.preferred_cleaners
  WHERE user_id = p_secondary OR cleaner_id = p_secondary;

  -- Drafts: one row per user_id
  IF EXISTS (SELECT 1 FROM public.cleaner_application_drafts WHERE user_id = p_primary) THEN
    DELETE FROM public.cleaner_application_drafts WHERE user_id = p_secondary;
  ELSE
    UPDATE public.cleaner_application_drafts SET user_id = p_primary WHERE user_id = p_secondary;
  END IF;

  -- cleaner_data: one row per user_id
  IF EXISTS (SELECT 1 FROM public.cleaner_data WHERE user_id = p_secondary) THEN
    IF EXISTS (SELECT 1 FROM public.cleaner_data WHERE user_id = p_primary) THEN
      UPDATE public.cleaner_data cd_p SET
        bio = COALESCE(NULLIF(trim(cd_p.bio), ''), cd_s.bio),
        skills = COALESCE(cd_p.skills, cd_s.skills),
        certifications = COALESCE(cd_p.certifications, cd_s.certifications),
        service_areas = COALESCE(cd_p.service_areas, cd_s.service_areas),
        hourly_rate = COALESCE(cd_p.hourly_rate, cd_s.hourly_rate),
        verified = COALESCE(cd_p.verified, cd_s.verified),
        rating = COALESCE(cd_p.rating, cd_s.rating),
        completed_jobs = GREATEST(COALESCE(cd_p.completed_jobs, 0), COALESCE(cd_s.completed_jobs, 0)),
        updated_at = now()
      FROM public.cleaner_data cd_s
      WHERE cd_p.user_id = p_primary AND cd_s.user_id = p_secondary;
      DELETE FROM public.cleaner_data WHERE user_id = p_secondary;
    ELSE
      UPDATE public.cleaner_data SET user_id = p_primary WHERE user_id = p_secondary;
    END IF;
  END IF;

  -- Roles: union then drop secondary
  INSERT INTO public.user_roles (user_id, role_id)
  SELECT p_primary, role_id FROM public.user_roles WHERE user_id = p_secondary
  ON CONFLICT (user_id, role_id) DO NOTHING;
  DELETE FROM public.user_roles WHERE user_id = p_secondary;

  -- Profiles: create primary from secondary when missing, else merge fields
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_secondary) THEN
    INSERT INTO public.profiles (
      id,
      user_id,
      firstname,
      lastname,
      fullname,
      bio,
      address,
      avatar_url,
      notification_settings,
      preferences,
      location_wkt,
      updated_at
    )
    SELECT
      p_primary,
      p_primary,
      s.firstname,
      s.lastname,
      s.fullname,
      s.bio,
      s.address,
      s.avatar_url,
      s.notification_settings,
      s.preferences,
      s.location_wkt,
      now()
    FROM public.profiles s
    WHERE s.id = p_secondary
      AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_primary);

    UPDATE public.profiles p SET
      firstname = COALESCE(NULLIF(trim(p.firstname), ''), s.firstname),
      lastname = COALESCE(NULLIF(trim(p.lastname), ''), s.lastname),
      fullname = COALESCE(NULLIF(trim(p.fullname), ''), s.fullname),
      bio = COALESCE(NULLIF(trim(p.bio), ''), s.bio),
      address = COALESCE(NULLIF(trim(p.address), ''), s.address),
      avatar_url = COALESCE(NULLIF(trim(p.avatar_url), ''), s.avatar_url),
      notification_settings = COALESCE(p.notification_settings, s.notification_settings),
      preferences = COALESCE(p.preferences, s.preferences),
      location_wkt = COALESCE(p.location_wkt, s.location_wkt),
      updated_at = now()
    FROM public.profiles s
    WHERE p.id = p_primary AND s.id = p_secondary;

    DELETE FROM public.profiles WHERE id = p_secondary;
  END IF;

  -- Contact fields on primary public.users mirror
  UPDATE public.users p SET
    email = COALESCE(p.email, s.email),
    phone = COALESCE(p.phone, s.phone),
    updated_at = now(),
    last_updated = now()
  FROM public.users s
  WHERE p.id = p_primary AND s.id = p_secondary;

  DELETE FROM public.users WHERE id = p_secondary;

  INSERT INTO public.account_merges (primary_user_id, secondary_user_id, merged_by, snapshot)
  VALUES (p_primary, p_secondary, p_merged_by, v_snapshot);

  RETURN v_snapshot;
END;
$$;


ALTER FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") IS 'Admin-only: move secondary user FK rows onto primary and delete secondary public.users. Auth user cleanup is done in app layer.';



CREATE OR REPLACE FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
  WITH compact AS (
    SELECT regexp_replace(trim(p_input), '[\s\-()]', '', 'g') AS c
  ),
  plus2330_fix AS (
    SELECT
      CASE
        WHEN c ~ '^\+2330[2-5][0-9]{8}$'
        THEN '+233' || substr(c, 6)
        ELSE c
      END AS c2
    FROM compact
  ),
  extracted AS (
    SELECT (regexp_match(c2, '^(?:\+?233|0)?([2-5][0-9]{8})$'))[1] AS nsn
    FROM plus2330_fix
  )
  SELECT CASE WHEN nsn IS NULL THEN NULL ELSE '+233' || nsn END
  FROM extracted;
$_$;


ALTER FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") IS 'Ghana mobile E.164 aligned with lib/phone-auth normalizeGhanaPhoneToE164 (+2330 collapse, NSN [2-5]…).';



CREATE OR REPLACE FUNCTION "public"."normalize_ghana_phone_to_e164"("p_input" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
  v_raw    text;
  v_digits text;
BEGIN
  IF p_input IS NULL THEN
    RETURN NULL;
  END IF;

  v_raw := regexp_replace(trim(p_input), '[\s-]', '', 'g');

  IF v_raw = '' OR position('@' in v_raw) > 0 THEN
    RETURN NULL;
  END IF;

  IF left(v_raw, 1) = '+' THEN
    v_digits := substring(v_raw from 2);
  ELSE
    v_digits := v_raw;
  END IF;

  IF v_digits !~ '^\d+$' THEN
    RETURN NULL;
  END IF;

  IF left(v_digits, 3) = '233' AND length(v_digits) = 12 THEN
    RETURN '+' || v_digits;
  END IF;

  IF left(v_digits, 1) = '0' AND length(v_digits) = 10 THEN
    RETURN '+233' || substring(v_digits from 2);
  END IF;

  IF length(v_digits) = 9 THEN
    RETURN '+233' || v_digits;
  END IF;

  RETURN NULL;
END;
$_$;


ALTER FUNCTION "public"."normalize_ghana_phone_to_e164"("p_input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_phone_for_users"("raw_phone" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
  cleaned text;
  digits text;
BEGIN
  IF raw_phone IS NULL OR btrim(raw_phone) = '' THEN
    RETURN NULL;
  END IF;

  -- Remove spaces, dashes, parentheses, dots.
  cleaned := regexp_replace(btrim(raw_phone), '[\s\-\(\)\.]', '', 'g');

  -- Convert international 00-prefix to + (e.g. 00233...).
  IF cleaned ~ '^00[1-9][0-9]{6,14}$' THEN
    cleaned := '+' || substring(cleaned from 3);
  END IF;

  -- Canonical E.164 with plus.
  IF cleaned ~ '^\+[1-9][0-9]{6,14}$' THEN
    RETURN '+' || regexp_replace(cleaned, '\D', '', 'g');
  END IF;

  digits := regexp_replace(cleaned, '\D', '', 'g');

  -- Ghana local: 0241234567 -> +233241234567.
  IF digits ~ '^0[2-5][0-9]{8}$' THEN
    RETURN '+233' || substring(digits from 2);
  END IF;

  -- Ghana common mistake: 2330241234567 -> +233241234567.
  IF digits ~ '^2330[2-5][0-9]{8}$' THEN
    RETURN '+233' || substring(digits from 5);
  END IF;

  -- Ghana without plus: 233241234567 -> +233241234567.
  IF digits ~ '^233[2-5][0-9]{8}$' THEN
    RETURN '+233' || substring(digits from 4);
  END IF;

  RETURN NULL;
END;
$_$;


ALTER FUNCTION "public"."normalize_phone_for_users"("raw_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."phone_lookup_variants"("p_raw" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE PARALLEL SAFE
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_trimmed text;
  v_sanitized text;
  v_digits text;
  v_national text;
  v_e164 text;
  v_variants text[] := ARRAY[]::text[];
BEGIN
  v_trimmed := trim(coalesce(p_raw, ''));
  IF v_trimmed = '' THEN
    RETURN v_variants;
  END IF;

  v_sanitized := regexp_replace(v_trimmed, '[^\d+]', '', 'g');
  v_digits := regexp_replace(v_sanitized, '\D', '', 'g');

  IF v_digits = '' THEN
    RETURN ARRAY[v_trimmed, v_sanitized]::text[];
  END IF;

  -- Ghana local: 0[2-5] + 8 digits (e.g. 0501234567)
  IF v_digits ~ '^0[2-5][0-9]{8}$' THEN
    v_national := substring(v_digits from 2);
    v_e164 := '+233' || v_national;
    v_variants := ARRAY[
      v_digits,
      v_national,
      '233' || v_national,
      v_e164,
      v_sanitized
    ];
  -- Ghana legacy: 2330[2-5] + 8 digits
  ELSIF v_digits ~ '^2330[2-5][0-9]{8}$' THEN
    v_national := substring(v_digits from 5);
    v_e164 := '+233' || v_national;
    v_variants := ARRAY[
      '0' || v_national,
      v_national,
      '233' || v_national,
      v_e164,
      v_digits,
      v_sanitized
    ];
  -- Ghana without leading +: 233[2-5] + 8 digits
  ELSIF v_digits ~ '^233[2-5][0-9]{8}$' THEN
    v_national := substring(v_digits from 4);
    v_e164 := '+233' || v_national;
    v_variants := ARRAY[
      '0' || v_national,
      v_national,
      v_digits,
      v_e164,
      v_sanitized
    ];
  -- Ghana national only: [2-5] + 8 digits (e.g. 501234567)
  ELSIF v_digits ~ '^[2-5][0-9]{8}$' THEN
    v_national := v_digits;
    v_e164 := '+233' || v_national;
    v_variants := ARRAY[
      '0' || v_national,
      v_national,
      '233' || v_national,
      v_e164,
      v_sanitized
    ];
  -- International / other E.164 stored as +digits
  ELSIF v_sanitized ~ '^\+' AND v_digits ~ '^[1-9][0-9]{6,14}$' THEN
    v_e164 := '+' || v_digits;
    v_variants := ARRAY[v_e164, v_digits, v_sanitized];
    -- If this is Ghana E.164, add local variants too
    IF v_digits ~ '^233[2-5][0-9]{8}$' THEN
      v_national := substring(v_digits from 4);
      v_variants := v_variants || ARRAY[
        '0' || v_national,
        v_national,
        '233' || v_national
      ];
    END IF;
  -- Bare international digits without +
  ELSIF v_digits ~ '^[1-9][0-9]{6,14}$' THEN
    v_e164 := '+' || v_digits;
    v_variants := ARRAY[v_digits, v_e164, v_sanitized];
    IF v_digits ~ '^233[2-5][0-9]{8}$' THEN
      v_national := substring(v_digits from 4);
      v_variants := v_variants || ARRAY[
        '0' || v_national,
        v_national
      ];
    END IF;
  ELSE
    v_variants := ARRAY[v_digits, v_sanitized, v_trimmed];
  END IF;

  SELECT coalesce(array_agg(DISTINCT x), ARRAY[]::text[])
  INTO v_variants
  FROM unnest(v_variants) AS x
  WHERE x IS NOT NULL AND btrim(x) <> '';

  RETURN v_variants;
END;
$_$;


ALTER FUNCTION "public"."phone_lookup_variants"("p_raw" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."phone_lookup_variants"("p_raw" "text") IS 'E.164 and legacy Ghana/international variants for phone identity matching (read-only).';



CREATE OR REPLACE FUNCTION "public"."psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") RETURNS "public"."psk_transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_new_transaction public.psk_transaction;
BEGIN
    INSERT INTO public.psk_transaction (
        booking_id,
        user_id,
        reference,
        paystack_id,
        amount,
        fee_amount,
        total_captured,
        currency,
        metadata
    )
    VALUES (
        p_booking_id,
        p_user_id,
        p_reference,
        p_paystack_id,
        p_amount,
        p_fee_amount,
        p_total_captured,
        p_currency,
        p_metadata
    )
    RETURNING * INTO v_new_transaction;

    RETURN v_new_transaction;
END;
$$;


ALTER FUNCTION "public"."psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone DEFAULT ("now"() + '24:00:00'::interval)) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_object_path IS NULL OR btrim(p_object_path) = '' THEN
    RAISE EXCEPTION 'object_path is required' USING ERRCODE = '22004';
  END IF;

  IF btrim(p_object_path) NOT LIKE v_user_id::text || '/%' THEN
    RAISE EXCEPTION 'Invalid avatar object path' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.avatar_storage_deletions (user_id, bucket, object_path, delete_after)
  VALUES (v_user_id, 'avatars', btrim(p_object_path), p_delete_after)
  ON CONFLICT ON CONSTRAINT avatar_storage_deletions_bucket_object_path_key
  DO UPDATE SET
    delete_after = EXCLUDED.delete_after,
    user_id = EXCLUDED.user_id;
END;
$$;


ALTER FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  bucket  timestamptz := date_trunc('second', now())
                       - (extract(epoch from now())::bigint % p_window_seconds) * interval '1 second';
  current integer;
begin
  insert into public.auth_lookup_rate_limit (scope, key, window_start, attempts)
  values (p_scope, p_key, bucket, 1)
  on conflict (scope, key, window_start)
  do update set attempts = public.auth_lookup_rate_limit.attempts + 1
  returning attempts into current;

  return current > p_max_attempts;
end;
$$;


ALTER FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_auth_identity_lookup"("target_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  auth_user auth.users%rowtype;
  normalized_email text;
  computed_phone_e164 text;
  computed_phone_variants text[];
  identity_providers text[];
  metadata_providers text[];
  merged_providers text[];
begin
  select *
  into auth_user
  from auth.users
  where id = target_user_id;

  if not found then
    delete from public.auth_identity_lookup where user_id = target_user_id;
    return;
  end if;

  normalized_email := nullif(lower(trim(coalesce(auth_user.email, ''))), '');

  select
    coalesce(v.phone_e164, null),
    coalesce(v.phone_variants, '{}'::text[])
  into
    computed_phone_e164,
    computed_phone_variants
  from public.compute_ghana_phone_variants(auth_user.phone) as v;

  select
    coalesce(
      array_agg(distinct lower(trim(i.provider)))
        filter (where i.provider is not null and trim(i.provider) <> ''),
      '{}'::text[]
    )
  into identity_providers
  from auth.identities i
  where i.user_id = target_user_id;

  if jsonb_typeof(auth_user.raw_app_meta_data -> 'providers') = 'array' then
    select
      coalesce(
        array_agg(distinct lower(trim(provider_value)))
          filter (where provider_value is not null and trim(provider_value) <> ''),
        '{}'::text[]
      )
    into metadata_providers
    from jsonb_array_elements_text(auth_user.raw_app_meta_data -> 'providers') as provider_value;
  elsif nullif(trim(coalesce(auth_user.raw_app_meta_data ->> 'provider', '')), '') is not null then
    metadata_providers := array[lower(trim(auth_user.raw_app_meta_data ->> 'provider'))];
  else
    metadata_providers := '{}'::text[];
  end if;

  select
    coalesce(
      array_agg(distinct provider_value)
        filter (where provider_value is not null and trim(provider_value) <> ''),
      '{}'::text[]
    )
  into merged_providers
  from unnest(coalesce(identity_providers, '{}'::text[]) || coalesce(metadata_providers, '{}'::text[])) as provider_value;

  insert into public.auth_identity_lookup (
    user_id,
    email,
    email_normalized,
    phone,
    phone_e164,
    phone_variants,
    providers,
    updated_at
  )
  values (
    auth_user.id,
    auth_user.email,
    normalized_email,
    auth_user.phone,
    computed_phone_e164,
    coalesce(computed_phone_variants, '{}'::text[]),
    coalesce(merged_providers, '{}'::text[]),
    now()
  )
  on conflict (user_id) do update
  set
    email = excluded.email,
    email_normalized = excluded.email_normalized,
    phone = excluded.phone,
    phone_e164 = excluded.phone_e164,
    phone_variants = excluded.phone_variants,
    providers = excluded.providers,
    updated_at = now();
end;
$$;


ALTER FUNCTION "public"."refresh_auth_identity_lookup"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RAISE EXCEPTION 'token is required' USING ERRCODE = '22004';
  END IF;

  IF p_platform NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'invalid platform' USING ERRCODE = '22023';
  END IF;

  -- Legacy accounts may exist in auth.users without a public.users shell row.
  INSERT INTO public.users (id, email)
  SELECT au.id, au.email
  FROM auth.users AS au
  WHERE au.id = v_user_id
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.device_tokens (user_id, token, platform, updated_at)
  VALUES (v_user_id, btrim(p_token), p_platform, now())
  ON CONFLICT (token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    updated_at = EXCLUDED.updated_at;
END;
$$;


ALTER FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_cleaner_after_15min_hold"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  released_count integer := 0;
BEGIN
  UPDATE public.bookings
  SET
    cleaner_id = NULL,
    cleaner_hold_expires_at = NULL,
    status = CASE
      WHEN status IN ('confirmed', 'pending') AND COALESCE(payment_status, 'pending') <> 'paid'
        THEN 'pending'::public.booking_status
      ELSE status
    END,
    updated_at = now(),
    last_updated = now()
  WHERE cleaner_id IS NOT NULL
    AND COALESCE(payment_status, 'pending') <> 'paid'
    AND status IN ('confirmed', 'pending') 
    AND (
      payment_status = 'failed'
      OR (
        cleaner_assigned_at IS NOT NULL
        AND cleaner_assigned_at::timestamptz <= (now() - interval '15 minutes')::timestamptz
      )
    );

  GET DIAGNOSTICS released_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'released_count', released_count
  );
END;
$$;


ALTER FUNCTION "public"."release_cleaner_after_15min_hold"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  n int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_co_cleaner_id IS NULL OR p_co_cleaner_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_co_cleaner');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.cleaner_data
    WHERE user_id = v_uid AND verified IS TRUE
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'only_verified_leads_can_remove');
  END IF;

  DELETE FROM public.co_cleaner_relationships
  WHERE lead_cleaner_id = v_uid
    AND co_cleaner_id = p_co_cleaner_id;

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'co_cleaner_not_on_team');
  END IF;

  RETURN jsonb_build_object('success', true, 'co_cleaner_id', p_co_cleaner_id);
END;
$$;


ALTER FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  n int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  UPDATE public.co_cleaner_invitations
  SET status = 'revoked', updated_at = now()
  WHERE id = p_invite_id
    AND inviter_user_id = v_uid
    AND status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found_or_not_pending');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  n int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  UPDATE public.preferred_cleaner_invitations
  SET status = 'revoked', updated_at = now()
  WHERE id = p_invite_id
    AND inviter_user_id = v_uid
    AND status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found_or_not_pending');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_available_cleaners"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[] DEFAULT '{}'::"text"[], "p_max_distance_meters" double precision DEFAULT 50000, "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("cleaner_id" "uuid", "cleaner_name" "text", "avatar_url" "text", "rating" double precision, "distance_meters" double precision, "matching_skills_count" integer, "total_skills_count" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_cust_loc geography := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  v_booking_range tstzrange := tstzrange(
    (p_date + p_time)::timestamptz,
    (p_date + p_time + (p_duration || ' hours')::interval)::timestamptz,
    '[)'
  );
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT
    cd.user_id,
    p.fullname,
    p.avatar_url,
    cd.rating::float,
    (cd.base_location::geography <-> v_cust_loc)::float AS dist_m,
    (
      SELECT count(*)::int
      FROM unnest(p_requested_services) s
      WHERE s = ANY(cd.skills) OR s = ANY(cd.specialties)
    ) AS matching_skills_count,
    COALESCE(array_length(cd.skills, 1), 0) AS total_skills_count
  FROM public.cleaner_data cd
  JOIN public.profiles p ON p.id = cd.user_id
  WHERE cd.status = 'active'
    AND (
      auth.uid() = cd.user_id
      OR public.is_profile_discoverable_by_others(p)
    )
    AND ST_DWithin(cd.base_location::geography, v_cust_loc, p_max_distance_meters)
    AND NOT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.cleaner_id = cd.user_id
        AND b.booking_period && v_booking_range
        AND b.status != 'cancelled'
        AND (
          p_exclude_booking_id IS NULL
          OR b.id <> p_exclude_booking_id
        )
    )
  ORDER BY cd.base_location::geography <-> v_cust_loc ASC;
END;
$$;


ALTER FUNCTION "public"."search_available_cleaners"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision, "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_available_cleaners_old"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[] DEFAULT '{}'::"text"[], "p_max_distance_meters" double precision DEFAULT 50000) RETURNS TABLE("cleaner_id" "uuid", "cleaner_name" "text", "avatar_url" "text", "rating" double precision, "distance_meters" double precision, "matching_skills_count" integer, "total_skills_count" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_cust_loc geography := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  v_booking_range tstzrange := tstzrange(
    (p_date + p_time)::timestamptz,
    (p_date + p_time + (p_duration || ' hours')::interval)::timestamptz,
    '[)'
  );
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT
    cd.user_id,
    p.fullname,
    p.avatar_url,
    cd.rating::float,
    (cd.base_location::geography <-> v_cust_loc)::float AS dist_m,
    (
      SELECT count(*)::int
      FROM unnest(p_requested_services) s
      WHERE s = ANY(cd.skills) OR s = ANY(cd.specialties)
    ) AS matching_skills_count,
    COALESCE(array_length(cd.skills, 1), 0) AS total_skills_count
  FROM public.cleaner_data cd
  JOIN public.profiles p ON p.id = cd.user_id
  WHERE cd.status = 'active'
    AND (
      auth.uid() = cd.user_id
      OR public.is_profile_discoverable_by_others(p)
    )
    AND ST_DWithin(cd.base_location::geography, v_cust_loc, p_max_distance_meters)
    AND NOT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.cleaner_id = cd.user_id
        AND b.booking_period && v_booking_range
        AND b.status != 'cancelled'
    )
  ORDER BY cd.base_location::geography <-> v_cust_loc ASC;
END;
$$;


ALTER FUNCTION "public"."search_available_cleaners_old"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_timezone"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- 1. Perform the spatial lookup
  SELECT tzid INTO NEW.timezone_name 
  FROM public.timezones
  WHERE ST_Intersects(geom, NEW.location_coordinates)
  LIMIT 1;
  
  -- 2. Safety Fallback: Default to UTC if no zone is found
  IF NEW.timezone_name IS NULL THEN
    NEW.timezone_name := 'UTC';
    RAISE WARNING 'No timezone found for point %, defaulting to UTC', ST_AsText(NEW.location_coordinates);
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_booking_timezone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_cleaner_assigned_at_for_hold"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Paid bookings: only clear legacy expiry column; do not reset hold/assignment timestamps.
  IF COALESCE(NEW.payment_status, 'pending') = 'paid' THEN
    NEW.cleaner_hold_expires_at := NULL;
    RETURN NEW;
  END IF;

  IF NEW.cleaner_id IS NOT NULL
     AND COALESCE(NEW.payment_status, 'pending') <> 'paid'
     AND (
       TG_OP = 'INSERT'
       OR OLD.cleaner_id IS NULL
       OR OLD.cleaner_id IS DISTINCT FROM NEW.cleaner_id
     )
  THEN
    NEW.cleaner_assigned_at := now();
    NEW.cleaner_hold_expires_at := NULL;
  END IF;

  -- Cron may clear cleaner_id but keep cleaner_assigned_at for "hold expired" detection.
  IF NEW.cleaner_id IS NULL THEN
    NEW.cleaner_hold_expires_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_cleaner_assigned_at_for_hold"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_purpose text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_method_id';
  END IF;

  SELECT pm.purpose
  INTO v_purpose
  FROM public.payout_methods pm
  WHERE pm.id = p_method_id
    AND pm.user_id = v_uid;

  IF v_purpose IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.payout_methods
  SET is_default = (id = p_method_id)
  WHERE user_id = v_uid
    AND purpose = v_purpose;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") IS 'Sets exactly one default payout/refund method per auth.uid() and purpose in a single UPDATE.';



CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end $$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_auth_identity_lookup_from_auth_identities"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  perform public.refresh_auth_identity_lookup(coalesce(new.user_id, old.user_id));
  return coalesce(new, old);
end;
$$;


ALTER FUNCTION "public"."sync_auth_identity_lookup_from_auth_identities"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_auth_identity_lookup_from_auth_users"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  perform public.refresh_auth_identity_lookup(coalesce(new.id, old.id));
  return coalesce(new, old);
end;
$$;


ALTER FUNCTION "public"."sync_auth_identity_lookup_from_auth_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_auth_user_to_public_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  meta_first text;
  meta_last text;
  meta_full text;
begin
  meta_first := nullif(trim(coalesce(new.raw_user_meta_data->>'first_name', '')), '');
  meta_last := nullif(trim(coalesce(new.raw_user_meta_data->>'last_name', '')), '');
  meta_full := nullif(
    trim(
      coalesce(
        new.raw_user_meta_data->>'full_name',
        new.raw_user_meta_data->>'name',
        concat_ws(' ', meta_first, meta_last)
      )
    ),
    ''
  );

  insert into public.users (id, email, phone, updated_at, last_updated)
  values (new.id, new.email, new.phone, now(), now())
  on conflict (id) do update
  set
    email = excluded.email,
    phone = coalesce(excluded.phone, public.users.phone),
    updated_at = now(),
    last_updated = now();

  insert into public.profiles (id, user_id, firstname, lastname, fullname, updated_at)
  values (new.id, new.id, meta_first, meta_last, meta_full, now())
  on conflict (id) do update
  set
    firstname = case
      when nullif(trim(coalesce(public.profiles.firstname, '')), '') is null
        then coalesce(excluded.firstname, public.profiles.firstname)
      else public.profiles.firstname
    end,
    lastname = case
      when nullif(trim(coalesce(public.profiles.lastname, '')), '') is null
        then coalesce(excluded.lastname, public.profiles.lastname)
      else public.profiles.lastname
    end,
    fullname = case
      when nullif(trim(coalesce(public.profiles.fullname, '')), '') is null
        then coalesce(excluded.fullname, public.profiles.fullname)
      else public.profiles.fullname
    end,
    updated_at = now();

  insert into public.user_roles (user_id, role_id)
  values (new.id, coalesce(new.raw_app_meta_data->>'role', 'customer'))
  on conflict (user_id, role_id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."sync_auth_user_to_public_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_booking_refunds_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."touch_booking_refunds_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_payout_methods_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."touch_payout_methods_updated_at"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."touch_payout_methods_updated_at"() IS 'Keeps payout_methods.updated_at aligned with row mutations.';



CREATE OR REPLACE FUNCTION "public"."trigger_paystack_on_approval"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_service_role_jwt text;
BEGIN
  IF NEW.verified IS TRUE
     AND (OLD.verified IS DISTINCT FROM NEW.verified)
  THEN
    v_service_role_jwt := current_setting('app.settings.service_role_jwt', true);

    PERFORM net.http_post(
      url := 'https://jzevawnetjwnliamyilb.supabase.co/functions/v1/create-paystack-customer',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_jwt
      ),
      body := jsonb_build_object('record', row_to_json(NEW))
    );
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Don’t break the update if the HTTP call fails; just log it
    RAISE WARNING 'Error calling Paystack Edge Function for cleaner %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_paystack_on_approval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_booking_status"("p_booking_id" "uuid", "p_new_status" "public"."booking_status", "p_notes" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- 1. Update the main booking
    UPDATE public.bookings
    SET 
        status = p_new_status,
        last_updated = now(),
        updated_at = now()
    WHERE id = p_booking_id;

    -- 2. Optional: If p_notes was provided, update the most recent timeline entry
    -- (The trigger above already created the row, we just add the custom note)
    IF p_notes IS NOT NULL THEN
        UPDATE public.booking_timeline
        SET notes = p_notes
        WHERE booking_id = p_booking_id
        AND stage = p_new_status
        AND id = (SELECT id FROM public.booking_timeline WHERE booking_id = p_booking_id ORDER BY changed_at DESC LIMIT 1);
    END IF;
END;
$$;


ALTER FUNCTION "public"."update_booking_status"("p_booking_id" "uuid", "p_new_status" "public"."booking_status", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_conversation_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE conversations
  SET last_message_at = NEW.created_at,
      updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_conversation_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_last_updated_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN 
    NEW.last_updated = now(); 
    RETURN NEW; 
END;$$;


ALTER FUNCTION "public"."update_last_updated_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_geom    geometry(Point, 4326);
  v_geog    geography(Point, 4326);
  v_now     timestamptz := now();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_user_id AND ur.role_id = 'cleaner'
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  v_geom := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);
  v_geog := v_geom::geography;

  -- cleaner_data row may not yet exist for the very newest cleaners
  -- (approval RPC always creates one, but defence in depth).
  INSERT INTO public.cleaner_data (user_id, base_location, max_travel_distance_meters, updated_at)
  VALUES (
    v_user_id,
    v_geom,
    COALESCE(p_max_distance_meters, 30000),
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    base_location              = EXCLUDED.base_location,
    max_travel_distance_meters = COALESCE(EXCLUDED.max_travel_distance_meters, public.cleaner_data.max_travel_distance_meters),
    updated_at                 = v_now;

  -- profiles row exists for every signed-in user (created by trigger).
  UPDATE public.profiles
  SET location_wkt = v_geog,
      updated_at   = v_now
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'user_id',                    v_user_id,
    'latitude',                   p_lat,
    'longitude',                  p_lng,
    'max_travel_distance_meters', COALESCE(p_max_distance_meters, 30000)
  );
END;
$$;


ALTER FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer) IS 'Authenticated cleaner sets their own base location. Writes both cleaner_data.base_location (geometry) and profiles.location_wkt (geography) so the booking search RPCs see them. Errors: 42501 forbidden.';



CREATE OR REPLACE FUNCTION "public"."update_platform_fees_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_platform_fees_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_booking_timeslot"("p_start_time_12h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text" DEFAULT 'UTC'::"text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_start_24h numeric;
  v_start_hour int;
  v_start_minute int;
  v_period text;
  v_now_at_location timestamptz;
  v_work_day_end numeric;
  v_travel_buffer numeric;
BEGIN
  -- 1. Fetch Dynamic Settings
  SELECT value_numeric INTO v_work_day_end FROM booking_settings WHERE key = 'work_day_end';
  SELECT value_numeric INTO v_travel_buffer FROM booking_settings WHERE key = 'travel_buffer';

  v_work_day_end := COALESCE(v_work_day_end, 17.0); -- 5 PM
  v_travel_buffer := COALESCE(v_travel_buffer, 1.0); -- 1 Hour

  -- 2. Convert 12h string to decimal 24h
  v_period := upper(trim(split_part(p_start_time_12h, ' ', 2)));
  v_start_hour := split_part(split_part(p_start_time_12h, ' ', 1), ':', 1)::int;
  v_start_minute := split_part(split_part(p_start_time_12h, ' ', 1), ':', 2)::int;
  
  IF v_period = 'PM' AND v_start_hour != 12 THEN v_start_hour := v_start_hour + 12;
  ELSIF v_period = 'AM' AND v_start_hour = 12 THEN v_start_hour := 0;
  END IF;
  
  v_start_24h := v_start_hour + (v_start_minute / 60.0);
  
  -- 3. Get local time at the property
  v_now_at_location := now() AT TIME ZONE p_timezone;

  -- 4. HARD STOP RULE: (Start + Duration + Buffer) cannot exceed 5 PM
  IF (v_start_24h + p_duration_hours + v_travel_buffer) > v_work_day_end THEN
    RETURN false;
  END IF;

  -- 5. REAL-TIME AVAILABILITY CHECK
  -- Construct the timestamp of the requested slot
  IF (p_booking_date + (v_start_hour * interval '1 hour') + (v_start_minute * interval '1 minute')) 
      AT TIME ZONE p_timezone < v_now_at_location THEN
    -- If the slot is in the past globally, it's impossible
    RETURN false;
  END IF;

  -- 6. DYNAMIC CUTOFF CHECK
  -- If it's currently past the time where (CurrentTime + Duration + Buffer) > 5 PM,
  -- then same-day booking is effectively disabled.
  IF p_booking_date = v_now_at_location::date THEN
    IF (EXTRACT(HOUR FROM v_now_at_location) + (EXTRACT(MINUTE FROM v_now_at_location)/60.0) 
        + p_duration_hours + v_travel_buffer) > v_work_day_end THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."validate_booking_timeslot"("p_start_time_12h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_booking_timeslot_24h"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text" DEFAULT 'UTC'::"text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
  v_start_hour int;
  v_start_minute int;
  v_start_24h numeric;

  v_now_local timestamp;   -- local wall-clock time at location
  v_slot_local timestamp;  -- slot wall-clock timestamp at location

  v_work_day_end numeric;
  v_travel_buffer numeric;

  v_time_clean text;
BEGIN
  -- Basic sanity
  IF p_booking_date IS NULL OR p_duration_hours IS NULL OR p_duration_hours <= 0 THEN
    RETURN false;
  END IF;

  -- 1) Settings
  SELECT value_numeric INTO v_work_day_end FROM booking_settings WHERE key = 'work_day_end';
  SELECT value_numeric INTO v_travel_buffer FROM booking_settings WHERE key = 'travel_buffer';

  v_work_day_end := COALESCE(v_work_day_end, 17.0);   -- 5 PM
  v_travel_buffer := COALESCE(v_travel_buffer, 1.0);  -- 1 hour

  -- 2) Normalize + validate "HH24:MI"
  v_time_clean := trim(coalesce(p_start_time_24h, ''));

  IF v_time_clean !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RETURN false;
  END IF;

  v_start_hour := split_part(v_time_clean, ':', 1)::int;
  v_start_minute := split_part(v_time_clean, ':', 2)::int;

  v_start_24h := v_start_hour + (v_start_minute / 60.0);

  -- 3) Local "now" at property (wall clock)
  v_now_local := (now() AT TIME ZONE p_timezone);

  -- 4) HARD STOP RULE: (Start + Duration + Buffer) cannot exceed work_day_end
  IF (v_start_24h + p_duration_hours + v_travel_buffer) > v_work_day_end THEN
    RETURN false;
  END IF;

  -- 5) REAL-TIME AVAILABILITY CHECK (slot must not be in the past locally)
  v_slot_local :=
    (p_booking_date::timestamp
      + (v_start_hour * interval '1 hour')
      + (v_start_minute * interval '1 minute'));

  IF v_slot_local < v_now_local THEN
    RETURN false;
  END IF;

  -- 6) DYNAMIC CUTOFF CHECK:
  -- if it's too late today to complete (now + duration + buffer > work_day_end)
  IF p_booking_date = v_now_local::date THEN
    IF (EXTRACT(HOUR FROM v_now_local) + (EXTRACT(MINUTE FROM v_now_local) / 60.0)
        + p_duration_hours + v_travel_buffer) > v_work_day_end THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$_$;


ALTER FUNCTION "public"."validate_booking_timeslot_24h"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_booking_timeslot_24h_debug"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text" DEFAULT 'UTC'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
  v_start_hour int;
  v_start_minute int;
  v_start_24h numeric;

  v_now_local timestamp;
  v_slot_local timestamp;

  v_work_day_end numeric;
  v_travel_buffer numeric;

  v_reason text := 'ok';
BEGIN
  -- Settings
  SELECT value_numeric INTO v_work_day_end FROM booking_settings WHERE key = 'work_day_end';
  SELECT value_numeric INTO v_travel_buffer FROM booking_settings WHERE key = 'travel_buffer';

  v_work_day_end := COALESCE(v_work_day_end, 17.0);
  v_travel_buffer := COALESCE(v_travel_buffer, 1.0);

  -- Validate format
  IF p_start_time_24h !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'invalid_time_format',
      'input', p_start_time_24h
    );
  END IF;

  v_start_hour := split_part(p_start_time_24h, ':', 1)::int;
  v_start_minute := split_part(p_start_time_24h, ':', 2)::int;
  v_start_24h := v_start_hour + (v_start_minute / 60.0);

  v_now_local := now() AT TIME ZONE p_timezone;

  -- Build slot timestamp
  v_slot_local :=
    p_booking_date::timestamp
    + (v_start_hour * interval '1 hour')
    + (v_start_minute * interval '1 minute');

  -- Rule 1: end-of-day overflow
  IF (v_start_24h + p_duration_hours + v_travel_buffer) > v_work_day_end THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'exceeds_work_day_end',
      'start_24h', v_start_24h,
      'duration', p_duration_hours,
      'buffer', v_travel_buffer,
      'work_day_end', v_work_day_end
    );
  END IF;

  -- Rule 2: past time
  IF v_slot_local < v_now_local THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'slot_in_past',
      'slot_local', v_slot_local,
      'now_local', v_now_local
    );
  END IF;

  -- Rule 3: same-day cutoff
  IF p_booking_date = v_now_local::date THEN
    IF (
      extract(hour from v_now_local)
      + extract(minute from v_now_local)/60.0
      + p_duration_hours
      + v_travel_buffer
    ) > v_work_day_end THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', 'same_day_cutoff',
        'now_local', v_now_local
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'ok',
    'slot_local', v_slot_local,
    'now_local', v_now_local
  );
END;
$_$;


ALTER FUNCTION "public"."validate_booking_timeslot_24h_debug"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_merges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "primary_user_id" "uuid" NOT NULL,
    "secondary_user_id" "uuid" NOT NULL,
    "merged_by" "uuid",
    "merged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "snapshot" "jsonb",
    CONSTRAINT "account_merges_distinct_users" CHECK (("primary_user_id" <> "secondary_user_id"))
);


ALTER TABLE "public"."account_merges" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_merges" IS 'Audit log when an admin merges two Instaclean accounts (secondary absorbed into primary).';



CREATE TABLE IF NOT EXISTS "public"."auth_identity_lookup" (
    "user_id" "uuid" NOT NULL,
    "email" "text",
    "email_normalized" "text",
    "phone" "text",
    "phone_e164" "text",
    "phone_variants" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "providers" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."auth_identity_lookup" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."auth_lookup_rate_limit" (
    "scope" "text" NOT NULL,
    "key" "text" NOT NULL,
    "window_start" timestamp with time zone NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."auth_lookup_rate_limit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."availability" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cleaner_id" "uuid",
    "start_time" timestamp with time zone NOT NULL,
    "end_time" timestamp with time zone NOT NULL,
    "is_recurring" boolean DEFAULT false,
    "day_of_week" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."availability" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."avatar_storage_deletions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "bucket" "text" DEFAULT 'avatars'::"text" NOT NULL,
    "object_path" "text" NOT NULL,
    "delete_after" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."avatar_storage_deletions" OWNER TO "postgres";


COMMENT ON TABLE "public"."avatar_storage_deletions" IS 'Storage objects to delete after the grace period when a user replaces their profile avatar.';



CREATE TABLE IF NOT EXISTS "public"."base_durations" (
    "id" "text" NOT NULL,
    "label" "text" NOT NULL,
    "hours" numeric(3,1) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."base_durations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_refunds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "tier" "text" NOT NULL,
    "refund_percent" integer NOT NULL,
    "refund_amount_minor" integer DEFAULT 0 NOT NULL,
    "paystack_transaction_reference" "text",
    "paystack_refund_reference" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "failure_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_refunds_refund_amount_minor_check" CHECK (("refund_amount_minor" >= 0)),
    CONSTRAINT "booking_refunds_refund_percent_check" CHECK (("refund_percent" = ANY (ARRAY[0, 50, 100]))),
    CONSTRAINT "booking_refunds_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'processed'::"text", 'failed'::"text", 'skipped'::"text", 'manual_review'::"text"]))),
    CONSTRAINT "booking_refunds_tier_check" CHECK (("tier" = ANY (ARRAY['full_refund'::"text", 'partial_refund'::"text", 'no_refund'::"text"])))
);


ALTER TABLE "public"."booking_refunds" OWNER TO "postgres";


COMMENT ON TABLE "public"."booking_refunds" IS 'One row per customer-cancelled booking: Paystack refund attempt + policy tier audit.';



CREATE TABLE IF NOT EXISTS "public"."booking_settings" (
    "key" "text" NOT NULL,
    "value_numeric" numeric,
    "description" "text"
);


ALTER TABLE "public"."booking_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_timeline" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid",
    "stage" "public"."booking_status" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "now"(),
    "notes" "text"
);


ALTER TABLE "public"."booking_timeline" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "cleaner_id" "uuid",
    "service_id" integer NOT NULL,
    "title" "text" NOT NULL,
    "scheduled_date" "date" NOT NULL,
    "scheduled_time" time without time zone NOT NULL,
    "duration_hours" numeric(4,1) DEFAULT 2.0 NOT NULL,
    "address" "text" NOT NULL,
    "special_instructions" "text",
    "status" "public"."booking_status" DEFAULT 'pending'::"public"."booking_status",
    "total_price" numeric NOT NULL,
    "platform_fee" numeric,
    "tax_amount" numeric,
    "payment_status" "text" DEFAULT 'pending'::"text",
    "payment_method" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_updated" timestamp with time zone DEFAULT "now"(),
    "booking_period" "tstzrange" NOT NULL,
    "timezone_name" "text",
    "location_coordinates" "public"."geometry"(Point,4326),
    "reference" "text",
    "home_size" "text",
    "extra_task_ids" "text"[] DEFAULT '{}'::"text"[],
    "duration_adjustment" numeric(3,1) DEFAULT 0,
    "duration_computed" numeric(3,1),
    "duration_final" numeric(3,1),
    "start_time_decimal" numeric GENERATED ALWAYS AS ((EXTRACT(hour FROM "scheduled_time") + (EXTRACT(minute FROM "scheduled_time") / 60.0))) STORED,
    "booking_cover" boolean,
    "booking_cover_amount" numeric,
    "timezone" "text" DEFAULT 'UTC'::"text",
    "completion_notes" "text",
    "customer_rating" smallint,
    "subscription_id" "uuid",
    "recurrence_interval" "text",
    "currency" "text" DEFAULT 'GHS'::"text",
    "pricing_version" "text" DEFAULT 'v1'::"text",
    "core_amount_minor" integer,
    "same_day_surcharge_minor" integer DEFAULT 0,
    "weekend_surcharge_minor" integer DEFAULT 0,
    "recurring_discount_minor" integer DEFAULT 0,
    "final_amount_minor" integer,
    "is_same_day" boolean,
    "is_weekend" boolean,
    "scheduled_at_utc" timestamp with time zone,
    "idempotency_key" "text",
    "service_duration_option_id" "uuid",
    "cancelled_at" timestamp with time zone,
    "cancellation_tier" "text",
    "cancelled_by" "uuid",
    "cancellation_reason" "text",
    "cleaner_assigned_at" timestamp with time zone,
    "cleaner_hold_expires_at" timestamp with time zone,
    "ops_new_booking_notice_sent_at" timestamp with time zone,
    "ops_confirmed_reminder_sent_at" timestamp with time zone,
    CONSTRAINT "bookings_cancellation_tier_check" CHECK ((("cancellation_tier" IS NULL) OR ("cancellation_tier" = ANY (ARRAY['full_refund'::"text", 'partial_refund'::"text", 'no_refund'::"text"])))),
    CONSTRAINT "bookings_core_amount_nonnegative_check" CHECK ((("core_amount_minor" IS NULL) OR ("core_amount_minor" >= 0))),
    CONSTRAINT "bookings_customer_rating_range" CHECK ((("customer_rating" IS NULL) OR (("customer_rating" >= 1) AND ("customer_rating" <= 5)))),
    CONSTRAINT "bookings_duration_hours_valid" CHECK ((("duration_hours" > (0)::numeric) AND ("duration_hours" <= (24)::numeric))),
    CONSTRAINT "bookings_final_amount_nonnegative_check" CHECK ((("final_amount_minor" IS NULL) OR ("final_amount_minor" >= 0))),
    CONSTRAINT "bookings_payment_status_check" CHECK ((("payment_status" IS NULL) OR ("payment_status" = ANY (ARRAY['pending'::"text", 'failed'::"text", 'paid'::"text", 'refunded'::"text", 'partially_refunded'::"text"])))),
    CONSTRAINT "bookings_recurrence_interval_check" CHECK ((("recurrence_interval" IS NULL) OR ("recurrence_interval" = ANY (ARRAY['weekly'::"text", 'bi-weekly'::"text", 'monthly'::"text"])))),
    CONSTRAINT "bookings_recurring_discount_nonnegative_check" CHECK (("recurring_discount_minor" >= 0)),
    CONSTRAINT "bookings_same_day_surcharge_nonnegative_check" CHECK (("same_day_surcharge_minor" >= 0)),
    CONSTRAINT "bookings_weekend_surcharge_nonnegative_check" CHECK (("weekend_surcharge_minor" >= 0))
);


ALTER TABLE "public"."bookings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."bookings"."completion_notes" IS 'Cleaner notes when marking job complete';



COMMENT ON COLUMN "public"."bookings"."customer_rating" IS 'Cleaner rating of customer experience (1-5)';



COMMENT ON COLUMN "public"."bookings"."cleaner_assigned_at" IS 'When cleaner_id was last set for an unpaid hold; release after 15 minutes server-side.';



COMMENT ON COLUMN "public"."bookings"."cleaner_hold_expires_at" IS 'Legacy optional expiry; prefer cleaner_assigned_at + interval. Keep null for new rows.';



COMMENT ON COLUMN "public"."bookings"."ops_new_booking_notice_sent_at" IS 'When ops support list was notified of this new booking (cron).';



COMMENT ON COLUMN "public"."bookings"."ops_confirmed_reminder_sent_at" IS 'When ops support list was reminded this paid confirmed booking still needs attention after the cron threshold.';



CREATE TABLE IF NOT EXISTS "public"."cleaner_application_drafts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text",
    "current_step" integer DEFAULT 1 NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_saved_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_reminded_at" timestamp with time zone,
    "ops_started_notice_sent_at" timestamp with time zone,
    "ops_stale_draft_reminder_sent_at" timestamp with time zone,
    CONSTRAINT "cleaner_application_drafts_email_normalized_chk" CHECK ((("email" = "lower"("email")) AND ("length"("btrim"("email")) > 0)))
);


ALTER TABLE "public"."cleaner_application_drafts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."cleaner_application_drafts"."last_reminded_at" IS 'Last time admin bulk/single reminder was successfully delivered (at least one channel).';



COMMENT ON COLUMN "public"."cleaner_application_drafts"."ops_started_notice_sent_at" IS 'First time ops list was notified this account saved a join-as-cleaner draft.';



COMMENT ON COLUMN "public"."cleaner_application_drafts"."ops_stale_draft_reminder_sent_at" IS 'Last time ops list received the 48h stale-draft reminder; cleared on draft save so silence can re-trigger.';



CREATE TABLE IF NOT EXISTS "public"."cleaner_applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text" NOT NULL,
    "bio" "text" NOT NULL,
    "skills" "text"[] DEFAULT '{}'::"text"[],
    "certifications" "text"[] DEFAULT '{}'::"text"[],
    "service_areas" "text"[] DEFAULT '{}'::"text"[],
    "hourly_rate" integer NOT NULL,
    "status" "text" DEFAULT 'pending'::"text",
    "availability" "jsonb" DEFAULT '{}'::"jsonb",
    "form_completed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_updated" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "kyc_provider" "text" DEFAULT 'sumsub'::"text" NOT NULL,
    "sumsub_applicant_id" "text",
    "sumsub_level_name" "text",
    "kyc_status" "text" DEFAULT 'not_started'::"text" NOT NULL,
    "kyc_review_answer" "text",
    "kyc_review_status" "text",
    "kyc_last_event_at" timestamp with time zone,
    "kyc_completed_at" timestamp with time zone,
    "kyc_provider_event" "text",
    "admin_feedback" "text",
    "reference1_name" "text",
    "reference1_phone" "text",
    "reference2_name" "text",
    "reference2_phone" "text",
    "service_type_ids" integer[] DEFAULT '{}'::integer[],
    "reference3_name" "text",
    "reference3_phone" "text",
    "reference1_relationship" "text",
    "reference2_relationship" "text",
    "reference3_relationship" "text",
    "has_cleaning_experience" boolean,
    "years_of_experience" "text",
    "previous_employers" "text",
    "hours_per_week" "text",
    "available_days" "text"[],
    "additional_skills" "text"[],
    "client_description" "text",
    "equipment_status" "text",
    "applicant_bio" "text",
    "ops_pending_review_reminder_sent_at" timestamp with time zone,
    CONSTRAINT "cleaner_applications_kyc_status_check" CHECK (("kyc_status" = ANY (ARRAY['not_started'::"text", 'pending'::"text", 'completed'::"text", 'rejected'::"text", 'on_hold'::"text"]))),
    CONSTRAINT "cleaner_applications_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'requested_info'::"text"])))
);


ALTER TABLE "public"."cleaner_applications" OWNER TO "postgres";


COMMENT ON COLUMN "public"."cleaner_applications"."availability" IS 'Join form snapshot JSON: availableDays, preferredShifts, startDate, hoursPerWeek.';



COMMENT ON COLUMN "public"."cleaner_applications"."reference1_relationship" IS 'Join form: relationship to reference / guarantor 1.';



COMMENT ON COLUMN "public"."cleaner_applications"."reference2_relationship" IS 'Join form: relationship to reference / guarantor 2.';



COMMENT ON COLUMN "public"."cleaner_applications"."reference3_relationship" IS 'Join form: relationship to reference / guarantor 3.';



COMMENT ON COLUMN "public"."cleaner_applications"."additional_skills" IS 'Free-form/additional skills from join form; cleaner_applications.skills holds specializations.';



COMMENT ON COLUMN "public"."cleaner_applications"."equipment_status" IS 'Join form: equipment answer label (web radio / WhatsApp mapped string).';



COMMENT ON COLUMN "public"."cleaner_applications"."applicant_bio" IS 'Join form step 1: applicant-written bio (distinct from composed review summary in bio).';



COMMENT ON COLUMN "public"."cleaner_applications"."ops_pending_review_reminder_sent_at" IS 'When ops list was emailed that this row was still pending review after 24h; cleared on each resubmit while pending.';



CREATE TABLE IF NOT EXISTS "public"."cleaner_availability_exceptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "exception_date" "date" NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cleaner_availability_exceptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_data" (
    "user_id" "uuid" NOT NULL,
    "verified" boolean DEFAULT false,
    "is_background_checked" boolean DEFAULT false,
    "rating" numeric(3,2) DEFAULT 0.00,
    "completed_jobs" numeric DEFAULT 0,
    "hourly_rate" numeric DEFAULT 0,
    "years_experience" numeric DEFAULT 0,
    "specialties" "text"[] DEFAULT '{}'::"text"[],
    "skills" "text"[] DEFAULT '{}'::"text"[],
    "languages" "text"[] DEFAULT '{English}'::"text"[],
    "certifications" "text"[] DEFAULT '{}'::"text"[],
    "work_history" "jsonb" DEFAULT '[]'::"jsonb",
    "service_areas" "text"[] DEFAULT '{}'::"text"[],
    "equipment_owned" "text"[] DEFAULT '{}'::"text"[],
    "status" "public"."cleaner_status" DEFAULT 'pending_verification'::"public"."cleaner_status",
    "is_online" boolean DEFAULT false,
    "last_online" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "base_location" "public"."geometry"(Point,4326),
    "max_travel_distance_meters" double precision DEFAULT 30000,
    "paystack_customer_id" "text",
    "bio" "text"
);


ALTER TABLE "public"."cleaner_data" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "expo_push_token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cleaner_devices_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text"])))
);


ALTER TABLE "public"."cleaner_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "name" "text",
    "area" "text",
    "experience" "text",
    "availability" "text",
    "step" "text" DEFAULT 'start'::"text" NOT NULL,
    "id_media_url" "text",
    "source" "text" DEFAULT 'whatsapp'::"text" NOT NULL,
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "current_step" "text" DEFAULT 'awaiting_apply'::"text" NOT NULL,
    "step_history" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "email" "text",
    "ghana_card_front_path" "text",
    "ghana_card_back_path" "text",
    "linked_user_id" "uuid",
    "submitted_at" timestamp with time zone,
    "web_continuation_code" "text",
    "web_continuation_code_expires_at" timestamp with time zone,
    "ops_started_notice_sent_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."cleaner_leads" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_leads" OWNER TO "postgres";


COMMENT ON COLUMN "public"."cleaner_leads"."payload" IS 'Structured pre-screen answers; claim into cleaner_application_drafts after signup.';



COMMENT ON COLUMN "public"."cleaner_leads"."web_continuation_code" IS '8-char Crockford base32 (no dash) for WEB continue flow; regenerated when user requests website link.';



COMMENT ON COLUMN "public"."cleaner_leads"."web_continuation_code_expires_at" IS 'TTL for web_continuation_code; enforced in app and Edge.';



COMMENT ON COLUMN "public"."cleaner_leads"."ops_started_notice_sent_at" IS 'First time ops list was notified this WhatsApp lead began APPLY (left awaiting_apply).';



CREATE TABLE IF NOT EXISTS "public"."cleaner_schedules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cleaner_id" "uuid",
    "day_of_week" "text" NOT NULL,
    "start_time" time without time zone NOT NULL,
    "end_time" time without time zone NOT NULL,
    CONSTRAINT "cleaner_schedules_day_of_week_check" CHECK (("day_of_week" = ANY (ARRAY['Monday'::"text", 'Tuesday'::"text", 'Wednesday'::"text", 'Thursday'::"text", 'Friday'::"text", 'Saturday'::"text", 'Sunday'::"text"])))
);


ALTER TABLE "public"."cleaner_schedules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_tracking" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "accuracy" double precision,
    "heading" double precision,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cleaner_tracking" OWNER TO "postgres";


COMMENT ON TABLE "public"."cleaner_tracking" IS 'GPS locations shared by cleaners during a booking for customer tracking';



CREATE TABLE IF NOT EXISTS "public"."cleaner_upload_link_tokens" (
    "upload_link_id" "uuid" NOT NULL,
    "upload_token" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cleaner_upload_link_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_upload_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "short_code" "text" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "side" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "used_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cleaner_upload_links_expires_after_created_ck" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "cleaner_upload_links_short_code_format_ck" CHECK (("short_code" ~ '^[A-Za-z0-9]{6,12}$'::"text")),
    CONSTRAINT "cleaner_upload_links_side_check" CHECK (("side" = ANY (ARRAY['front'::"text", 'back'::"text"])))
);


ALTER TABLE "public"."cleaner_upload_links" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cleaner_verifications" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "id_number" "text",
    "id_front_url" "text",
    "id_back_url" "text",
    "police_report_url" "text",
    "profile_photo_url" "text",
    "bio" "text",
    "service_area" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "date_of_birth" "date"
);


ALTER TABLE "public"."cleaner_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."co_cleaner_invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inviter_user_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invitee_email" "text",
    "invitee_phone_e164" "text",
    "expires_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "accepted_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "co_cleaner_invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'expired'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."co_cleaner_invitations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."co_cleaner_relationships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_cleaner_id" "uuid" NOT NULL,
    "co_cleaner_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "co_cleaner_relationships_check" CHECK (("lead_cleaner_id" <> "co_cleaner_id"))
);


ALTER TABLE "public"."co_cleaner_relationships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "last_message_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "messages_content_not_empty" CHECK (("length"(TRIM(BOTH FROM "content")) > 0))
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."conversation_list" AS
 SELECT "c"."id",
    "c"."customer_id",
    "c"."cleaner_id",
    "c"."booking_id",
    "c"."last_message_at",
    "c"."metadata",
    "c"."created_at",
    "c"."updated_at",
    ( SELECT "messages"."content"
           FROM "public"."messages"
          WHERE ("messages"."conversation_id" = "c"."id")
          ORDER BY "messages"."created_at" DESC
         LIMIT 1) AS "last_message_text",
    ( SELECT "count"(*) AS "count"
           FROM "public"."messages"
          WHERE (("messages"."conversation_id" = "c"."id") AND ("messages"."sender_id" <> "auth"."uid"()) AND ("messages"."read_at" IS NULL))) AS "unread_count",
    (("cust"."firstname" || ' '::"text") || "cust"."lastname") AS "customer_name",
    "cust"."avatar_url" AS "customer_avatar",
    (("cln"."firstname" || ' '::"text") || "cln"."lastname") AS "cleaner_name",
    "cln"."avatar_url" AS "cleaner_avatar"
   FROM (("public"."conversations" "c"
     JOIN "public"."profiles" "cust" ON (("c"."customer_id" = "cust"."id")))
     JOIN "public"."profiles" "cln" ON (("c"."cleaner_id" = "cln"."id")));


ALTER VIEW "public"."conversation_list" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."customer_bookings_view" AS
 SELECT "b"."id" AS "booking_id",
    "b"."customer_id",
    "b"."address",
    "b"."scheduled_date",
    "b"."scheduled_time",
    "b"."status",
    "b"."total_price",
    "b"."cleaner_id",
    COALESCE("p"."fullname", "concat_ws"(' '::"text", "p"."firstname", "p"."lastname")) AS "cleaner_name",
    "p"."avatar_url" AS "cleaner_avatar",
    "cd"."rating" AS "cleaner_rating",
    "cd"."completed_jobs" AS "cleaner_jobs"
   FROM (("public"."bookings" "b"
     LEFT JOIN "public"."profiles" "p" ON (("p"."id" = "b"."cleaner_id")))
     LEFT JOIN "public"."cleaner_data" "cd" ON (("cd"."user_id" = "b"."cleaner_id")));


ALTER VIEW "public"."customer_bookings_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deduction_rules" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "rate_percentage" numeric,
    "is_fixed_amount" boolean DEFAULT false,
    "fixed_amount" numeric DEFAULT 0,
    "start_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "end_date" timestamp with time zone,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."deduction_rules" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."deduction_rules_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."deduction_rules_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."deduction_rules_id_seq" OWNED BY "public"."deduction_rules"."id";



CREATE TABLE IF NOT EXISTS "public"."device_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text"])))
);


ALTER TABLE "public"."device_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discounts" (
    "id" integer NOT NULL,
    "service_type_id" integer,
    "amount" numeric NOT NULL,
    "description" "text",
    "valid_from" "date",
    "valid_to" "date",
    "category" "public"."service_category",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp without time zone
);


ALTER TABLE "public"."discounts" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."discounts_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."discounts_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."discounts_id_seq" OWNED BY "public"."discounts"."id";



CREATE TABLE IF NOT EXISTS "public"."email_signup_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "token_hash" "text" NOT NULL,
    "return_url" "text",
    "expires_at" timestamp with time zone NOT NULL,
    "used_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."email_signup_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."email_verifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "email" "text" NOT NULL,
    "name" "text",
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone,
    "verified" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."email_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."extra_tasks" (
    "id" "text" NOT NULL,
    "label" "text" NOT NULL,
    "hours" numeric(3,1) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "icon_key" "text"
);


ALTER TABLE "public"."extra_tasks" OWNER TO "postgres";


COMMENT ON COLUMN "public"."extra_tasks"."icon_key" IS 'Slug: oven, laundry, window, fridge, floor, dishes, bathroom, trash, bedding, wardrobe, upholstery, outdoor, ac, storage, clean. Null = derive from label and task id.';



CREATE TABLE IF NOT EXISTS "public"."feedback" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "ratings" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."feedback" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback_categories" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."feedback_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."geo_reverse_cache" (
    "key" "text" NOT NULL,
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "city" "text",
    "area" "text",
    "region" "text",
    "country" "text",
    "iso_country_code" "text",
    "display_name" "text",
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."geo_reverse_cache" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gha_staging" (
    "gid" integer NOT NULL,
    "featurecla" character varying(24),
    "scalerank" smallint,
    "adm1_code" character varying(9),
    "diss_me" integer,
    "iso_3166_2" character varying(8),
    "wikipedia" character varying(84),
    "iso_a2" character varying(2),
    "adm0_sr" smallint,
    "name" character varying(44),
    "name_alt" character varying(129),
    "name_local" character varying(66),
    "type" character varying(38),
    "type_en" character varying(27),
    "code_local" character varying(5),
    "code_hasc" character varying(8),
    "note" character varying(114),
    "hasc_maybe" character varying(13),
    "region" character varying(43),
    "region_cod" character varying(15),
    "provnum_ne" integer,
    "gadm_level" smallint,
    "check_me" smallint,
    "datarank" smallint,
    "abbrev" character varying(9),
    "postal" character varying(3),
    "area_sqkm" smallint,
    "sameascity" smallint,
    "labelrank" smallint,
    "name_len" smallint,
    "mapcolor9" smallint,
    "mapcolor13" smallint,
    "fips" character varying(5),
    "fips_alt" character varying(9),
    "woe_id" integer,
    "woe_label" character varying(64),
    "woe_name" character varying(44),
    "latitude" double precision,
    "longitude" double precision,
    "sov_a3" character varying(3),
    "adm0_a3" character varying(3),
    "adm0_label" smallint,
    "admin" character varying(36),
    "geonunit" character varying(40),
    "gu_a3" character varying(3),
    "gn_id" integer,
    "gn_name" character varying(72),
    "gns_id" integer,
    "gns_name" character varying(80),
    "gn_level" smallint,
    "gn_region" character varying(1),
    "gn_a1_code" character varying(10),
    "region_sub" character varying(41),
    "sub_code" character varying(5),
    "gns_level" smallint,
    "gns_lang" character varying(3),
    "gns_adm1" character varying(4),
    "gns_region" character varying(4),
    "min_label" double precision,
    "max_label" double precision,
    "min_zoom" double precision,
    "wikidataid" character varying(9),
    "name_ar" character varying(85),
    "name_bn" character varying(134),
    "name_de" character varying(50),
    "name_en" character varying(47),
    "name_es" character varying(44),
    "name_fr" character varying(47),
    "name_el" character varying(85),
    "name_hi" character varying(134),
    "name_hu" character varying(47),
    "name_id" character varying(46),
    "name_it" character varying(47),
    "name_ja" character varying(96),
    "name_ko" character varying(54),
    "name_nl" character varying(46),
    "name_pl" character varying(45),
    "name_pt" character varying(43),
    "name_ru" character varying(85),
    "name_sv" character varying(41),
    "name_tr" character varying(44),
    "name_vi" character varying(71),
    "name_zh" character varying(61),
    "ne_id" double precision,
    "name_he" character varying(63),
    "name_uk" character varying(89),
    "name_ur" character varying(103),
    "name_fa" character varying(92),
    "name_zht" character varying(61),
    "fclass_iso" character varying(12),
    "fclass_us" character varying(12),
    "fclass_fr" character varying(1),
    "fclass_ru" character varying(12),
    "fclass_es" character varying(12),
    "fclass_cn" character varying(18),
    "fclass_tw" character varying(12),
    "fclass_in" character varying(12),
    "fclass_np" character varying(12),
    "fclass_pk" character varying(12),
    "fclass_de" character varying(12),
    "fclass_gb" character varying(12),
    "fclass_br" character varying(12),
    "fclass_il" character varying(12),
    "fclass_ps" character varying(12),
    "fclass_sa" character varying(12),
    "fclass_eg" character varying(12),
    "fclass_ma" character varying(1),
    "fclass_pt" character varying(12),
    "fclass_ar" character varying(12),
    "fclass_jp" character varying(12),
    "fclass_ko" character varying(12),
    "fclass_vn" character varying(12),
    "fclass_tr" character varying(1),
    "fclass_id" character varying(12),
    "fclass_pl" character varying(1),
    "fclass_gr" character varying(12),
    "fclass_it" character varying(12),
    "fclass_nl" character varying(1),
    "fclass_se" character varying(12),
    "fclass_bd" character varying(12),
    "fclass_ua" character varying(12),
    "fclass_tlc" character varying(12),
    "geom" "public"."geometry"(MultiPolygon,4326)
);


ALTER TABLE "public"."gha_staging" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."gha_staging_gid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."gha_staging_gid_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."gha_staging_gid_seq" OWNED BY "public"."gha_staging"."gid";



CREATE TABLE IF NOT EXISTS "public"."home_size_durations" (
    "home_size" "text" NOT NULL,
    "base_hours" numeric(3,1) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "home_size_durations_base_hours_check" CHECK (("base_hours" >= (0)::numeric))
);


ALTER TABLE "public"."home_size_durations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inbound_messages" (
    "id" bigint NOT NULL,
    "from" "text",
    "to" "text",
    "body" "text",
    "message_sid" "text",
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."inbound_messages" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."inbound_messages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."inbound_messages_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."inbound_messages_id_seq" OWNED BY "public"."inbound_messages"."id";



CREATE TABLE IF NOT EXISTS "public"."invite_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "max_uses" integer DEFAULT 1 NOT NULL,
    "uses" integer DEFAULT 0 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "expires_at" timestamp with time zone,
    "created_by" "uuid",
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_role" "text" DEFAULT 'customer'::"text",
    CONSTRAINT "invite_codes_user_role_check" CHECK (("user_role" = ANY (ARRAY['customer'::"text", 'cleaner'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."invite_codes" OWNER TO "postgres";


COMMENT ON COLUMN "public"."invite_codes"."user_role" IS 'The user role this invite code is intended for: customer, cleaner, or admin';



CREATE TABLE IF NOT EXISTS "public"."job_offers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_id" "uuid" NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "job_offers_status_check" CHECK (("status" = ANY (ARRAY['sent'::"text", 'accepted'::"text", 'declined'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."job_offers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."job_photo_comparisons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "before_photo_url" "text" NOT NULL,
    "after_photo_url" "text" NOT NULL,
    "title" "text" DEFAULT 'Cleaning Transformation'::"text" NOT NULL,
    "description" "text" DEFAULT ''::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "composite_photo_url" "text"
);


ALTER TABLE "public"."job_photo_comparisons" OWNER TO "postgres";


COMMENT ON TABLE "public"."job_photo_comparisons" IS 'Before/after photo comparisons created by cleaners on job detail';



COMMENT ON COLUMN "public"."job_photo_comparisons"."composite_photo_url" IS 'Public URL of the generated before/after composite image for sharing';



CREATE TABLE IF NOT EXISTS "public"."jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "address_text" "text",
    "lat" double precision,
    "lng" double precision,
    "price" numeric NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "claimed_by" "uuid",
    "claimed_at" timestamp with time zone,
    "offer_expires_at" timestamp with time zone,
    CONSTRAINT "jobs_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'offered'::"text", 'claimed'::"text", 'canceled'::"text", 'expired'::"text", 'in_progress'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kyc_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "subject_type" "text" NOT NULL,
    "cleaner_application_id" "uuid",
    "sumsub_applicant_id" "text" NOT NULL,
    "sumsub_external_user_id" "text" NOT NULL,
    "kyc_status" "text" DEFAULT 'not_started'::"text" NOT NULL,
    "review_answer" "text",
    "review_reason" "text",
    "level_name" "text",
    "country_code" "text",
    "document_types" "text"[],
    "submitted_at" timestamp with time zone,
    "reviewed_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_event_type" "text",
    "last_event_created_at_ms" bigint,
    "last_webhook_payload" "jsonb",
    CONSTRAINT "kyc_profiles_kyc_status_check" CHECK (("kyc_status" = ANY (ARRAY['not_started'::"text", 'started'::"text", 'submitted'::"text", 'completed'::"text", 'approved'::"text", 'rejected'::"text", 'failed'::"text"]))),
    CONSTRAINT "kyc_profiles_subject_type_check" CHECK (("subject_type" = ANY (ARRAY['customer'::"text", 'cleaner'::"text", 'user'::"text"])))
);


ALTER TABLE "public"."kyc_profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."kyc_profiles"."subject_type" IS 'Canonical values: customer, cleaner. ''user'' is a legacy alias kept temporarily; remove once no writers emit it.';



CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "type" "public"."notification_type" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payment_split_config" (
    "key" "text" NOT NULL,
    "value" numeric NOT NULL,
    "description" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."payment_split_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payout_methods" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "recipient_code" "text" NOT NULL,
    "account_number" "text" NOT NULL,
    "type" "text" NOT NULL,
    "bank_name" "text",
    "bank_code" "text",
    "network" "text",
    "account_name" "text",
    "masked_account" "text" NOT NULL,
    "currency" "text" DEFAULT 'GHS'::"text",
    "is_primary" boolean DEFAULT false,
    "is_default" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "purpose" "text" DEFAULT 'payout'::"text" NOT NULL,
    CONSTRAINT "payout_methods_purpose_check" CHECK (("purpose" = ANY (ARRAY['payout'::"text", 'refund'::"text"])))
);


ALTER TABLE "public"."payout_methods" OWNER TO "postgres";


COMMENT ON TABLE "public"."payout_methods" IS 'Cleaner payout destinations; client CRUD is owner-scoped via RLS. Service role / Edge Functions bypass RLS.';



COMMENT ON COLUMN "public"."payout_methods"."updated_at" IS 'Maintained by BEFORE UPDATE trigger and default on INSERT.';



COMMENT ON COLUMN "public"."payout_methods"."purpose" IS 'payout = cleaner earnings destination; refund = customer refund destination. Same Paystack recipient_code may appear on both.';



CREATE TABLE IF NOT EXISTS "public"."payout_recipient_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "recipient_code" "text",
    "recipient_type" "text" NOT NULL,
    "currency" "text" NOT NULL,
    "masked_account" "text" NOT NULL,
    "bank_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "payout_recipient_audit_recipient_type_check" CHECK (("recipient_type" = ANY (ARRAY['nuban'::"text", 'mobile_money'::"text"])))
);


ALTER TABLE "public"."payout_recipient_audit" OWNER TO "postgres";


COMMENT ON TABLE "public"."payout_recipient_audit" IS 'Append-only audit log when Paystack transfer recipients are created or reused.';



CREATE TABLE IF NOT EXISTS "public"."platform_fees" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fee_type" "text" NOT NULL,
    "fee_value" numeric(10,2) NOT NULL,
    "description" "text",
    "is_default" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "platform_fees_fee_type_check" CHECK (("fee_type" = ANY (ARRAY['percentage'::"text", 'fixed'::"text"]))),
    CONSTRAINT "platform_fees_fee_value_check" CHECK (("fee_value" >= (0)::numeric))
);


ALTER TABLE "public"."platform_fees" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platform_settings" (
    "singleton" boolean DEFAULT true NOT NULL,
    "general" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "booking" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "payment" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "notification" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "security" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "platform_settings_singleton_check" CHECK (("singleton" = true))
);


ALTER TABLE "public"."platform_settings" OWNER TO "postgres";


COMMENT ON TABLE "public"."platform_settings" IS 'Singleton row for admin settings UI; each column is a JSON object merged with app defaults on read.';



CREATE TABLE IF NOT EXISTS "public"."preferred_cleaner_invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inviter_user_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invitee_email" "text",
    "invitee_phone_e164" "text",
    "expires_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "accepted_cleaner_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "preferred_cleaner_invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'expired'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."preferred_cleaner_invitations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."preferred_cleaners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "cleaner_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."preferred_cleaners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pricing_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pricing_version" "text" NOT NULL,
    "currency" "text" DEFAULT 'GHS'::"text" NOT NULL,
    "same_day_surcharge_bps" integer NOT NULL,
    "weekend_surcharge_bps" integer NOT NULL,
    "recurring_weekly_discount_bps" integer NOT NULL,
    "recurring_monthly_discount_bps" integer NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL,
    "effective_from" timestamp with time zone,
    "effective_to" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pricing_rules_effective_window_valid" CHECK ((("effective_to" IS NULL) OR ("effective_from" IS NULL) OR ("effective_to" > "effective_from"))),
    CONSTRAINT "pricing_rules_recurring_monthly_bps_range" CHECK ((("recurring_monthly_discount_bps" >= 0) AND ("recurring_monthly_discount_bps" <= 10000))),
    CONSTRAINT "pricing_rules_recurring_weekly_bps_range" CHECK ((("recurring_weekly_discount_bps" >= 0) AND ("recurring_weekly_discount_bps" <= 10000))),
    CONSTRAINT "pricing_rules_same_day_bps_range" CHECK ((("same_day_surcharge_bps" >= 0) AND ("same_day_surcharge_bps" <= 10000))),
    CONSTRAINT "pricing_rules_weekend_bps_range" CHECK ((("weekend_surcharge_bps" >= 0) AND ("weekend_surcharge_bps" <= 10000)))
);


ALTER TABLE "public"."pricing_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reviewer_permissions" (
    "user_id" "uuid" NOT NULL,
    "permission_key" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."reviewer_permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."reviewer_permissions" IS 'Keys match lib/auth/permissions.ts ReviewerPermissionKey; only users with user_roles.role_id = reviewer should have rows.';



CREATE TABLE IF NOT EXISTS "public"."reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reviewer_id" "uuid",
    "reviewee_id" "uuid",
    "rating" integer NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "booking_id" "uuid",
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."reviews" OWNER TO "postgres";


COMMENT ON COLUMN "public"."reviews"."booking_id" IS 'Booking this review is for; at most one review per booking';



CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_categories" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "icon" "text",
    "default_discount" integer,
    "slug" "text"
);


ALTER TABLE "public"."service_categories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."service_categories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."service_categories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."service_categories_id_seq" OWNED BY "public"."service_categories"."id";



CREATE TABLE IF NOT EXISTS "public"."service_duration_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "service_type_id" integer NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "label" "text" NOT NULL,
    "duration_hours" numeric(6,2) NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "service_duration_options_duration_hours_check" CHECK ((("duration_hours" >= (0)::numeric) AND ("duration_hours" <= (24)::numeric)))
);


ALTER TABLE "public"."service_duration_options" OWNER TO "postgres";


COMMENT ON TABLE "public"."service_duration_options" IS 'Per–service-type load/tier rows; duration_hours is billable hours (single source of truth).';



CREATE TABLE IF NOT EXISTS "public"."service_types" (
    "id" integer NOT NULL,
    "category_id" integer,
    "name" "text" NOT NULL,
    "price" numeric NOT NULL,
    "duration" "text" NOT NULL,
    "category" "public"."service_category" NOT NULL,
    "discount" numeric DEFAULT 0,
    "active" boolean DEFAULT true,
    "image_url" "text",
    "features" "text"[] DEFAULT '{}'::"text"[],
    "last_updated" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."service_types" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."service_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."service_types_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."service_types_id_seq" OWNED BY "public"."service_types"."id";



CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "cleaner_id" "uuid",
    "service_id" integer NOT NULL,
    "address" "text" NOT NULL,
    "duration_hours" integer DEFAULT 2 NOT NULL,
    "recurrence_interval" "text" NOT NULL,
    "paystack_subscription_code" "text",
    "paystack_plan_code" "text",
    "amount" integer NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "next_occurrence_date" "date",
    "scheduled_time" time without time zone,
    "home_size" "text",
    "extra_task_ids" "text"[] DEFAULT '{}'::"text"[],
    "special_instructions" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "location_coordinates" "public"."geometry"(Point,4326),
    "currency" "text" DEFAULT 'GHS'::"text",
    "pricing_version" "text" DEFAULT 'v1'::"text",
    "first_charge_amount_minor" integer,
    "recurring_amount_minor" integer,
    "discount_type" "text",
    "discount_rate_bps" integer DEFAULT 0,
    CONSTRAINT "subscriptions_discount_rate_bps_range_check" CHECK ((("discount_rate_bps" >= 0) AND ("discount_rate_bps" <= 10000))),
    CONSTRAINT "subscriptions_discount_type_check" CHECK (("discount_type" = ANY (ARRAY['none'::"text", 'weekly'::"text", 'bi-weekly'::"text", 'monthly'::"text"]))),
    CONSTRAINT "subscriptions_first_charge_amount_nonnegative_check" CHECK ((("first_charge_amount_minor" IS NULL) OR ("first_charge_amount_minor" >= 0))),
    CONSTRAINT "subscriptions_recurrence_interval_check" CHECK (("recurrence_interval" = ANY (ARRAY['weekly'::"text", 'bi-weekly'::"text", 'monthly'::"text"]))),
    CONSTRAINT "subscriptions_recurring_amount_nonnegative_check" CHECK ((("recurring_amount_minor" IS NULL) OR ("recurring_amount_minor" >= 0))),
    CONSTRAINT "subscriptions_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'cancelled'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."subscriptions" IS 'Recurring cleaning plans; each occurrence is a row in bookings with subscription_id set.';



CREATE TABLE IF NOT EXISTS "public"."testimonials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "location" "text" NOT NULL,
    "rating" smallint NOT NULL,
    "testimonial" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "testimonials_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."testimonials" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."timezones" (
    "gid" integer NOT NULL,
    "tzid" character varying(80),
    "geom" "public"."geometry"(MultiPolygon,4326)
);


ALTER TABLE "public"."timezones" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."timezones_gid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."timezones_gid_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."timezones_gid_seq" OWNED BY "public"."timezones"."gid";



CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "amount" numeric NOT NULL,
    "fee_amount" numeric DEFAULT 0,
    "total_captured" numeric NOT NULL,
    "currency" "text" DEFAULT 'GHS'::"text",
    "status" "text" NOT NULL,
    "type" "text" NOT NULL,
    "reference" "text",
    "recipient_code" "text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "customer_id" "uuid",
    "job_type" "text"
);


ALTER TABLE "public"."transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_login_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "user_email" "text",
    "ip_address" "text",
    "user_agent" "text",
    "browser_label" "text",
    "os_label" "text",
    "country" "text",
    "region" "text",
    "city" "text",
    "location_display" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_login_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_login_sessions" IS 'Append-only sign-in audit (IP, UA, coarse geo). Filled by app API; readable by super admins via service role.';



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "user_id" "uuid" NOT NULL,
    "role_id" "text" NOT NULL
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "phone" "text",
    "status" "public"."user_status" DEFAULT 'active'::"public"."user_status",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_updated" timestamp with time zone DEFAULT "now"(),
    "password_hash" "text",
    CONSTRAINT "users_phone_e164_chk" CHECK ((("phone" IS NULL) OR ("phone" ~ '^\+?[1-9][0-9]{7,14}$'::"text")))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wallet_deductions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "transaction_id" "text",
    "rule_id" integer,
    "amount_deducted" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wallet_deductions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wallet_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "wallet_id" "uuid",
    "booking_id" "uuid",
    "amount_subunit" integer NOT NULL,
    "type" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "wallet_transactions_type_check" CHECK (("type" = ANY (ARRAY['credit'::"text", 'debit'::"text"])))
);


ALTER TABLE "public"."wallet_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wallets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "balance_subunit" integer DEFAULT 0,
    "currency" character varying(3) DEFAULT 'GHS'::character varying,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wallets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."whatsapp_inbox_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "direction" "text" NOT NULL,
    "phone_e164" "text" NOT NULL,
    "body" "text" DEFAULT ''::"text" NOT NULL,
    "user_id" "uuid",
    "twilio_message_sid" "text",
    "sent_by_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "whatsapp_inbox_messages_direction_check" CHECK (("direction" = ANY (ARRAY['inbound'::"text", 'outbound'::"text"]))),
    CONSTRAINT "whatsapp_inbox_messages_phone_e164_check" CHECK (("phone_e164" ~ '^\+[1-9][0-9]{6,14}$'::"text"))
);


ALTER TABLE "public"."whatsapp_inbox_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."withdrawal_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cleaner_id" "uuid" NOT NULL,
    "wallet_id" "uuid" NOT NULL,
    "amount_subunit" integer NOT NULL,
    "status" "public"."withdrawal_status" DEFAULT 'pending'::"public"."withdrawal_status",
    "paystack_transfer_code" "text",
    "paystack_reference" "text",
    "bank_details" "jsonb",
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."withdrawal_requests" OWNER TO "postgres";


ALTER TABLE ONLY "public"."deduction_rules" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."deduction_rules_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."discounts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."discounts_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."gha_staging" ALTER COLUMN "gid" SET DEFAULT "nextval"('"public"."gha_staging_gid_seq"'::"regclass");



ALTER TABLE ONLY "public"."inbound_messages" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."inbound_messages_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."service_categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."service_categories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."service_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."service_types_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."timezones" ALTER COLUMN "gid" SET DEFAULT "nextval"('"public"."timezones_gid_seq"'::"regclass");



ALTER TABLE ONLY "public"."account_merges"
    ADD CONSTRAINT "account_merges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_identity_lookup"
    ADD CONSTRAINT "auth_identity_lookup_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."auth_lookup_rate_limit"
    ADD CONSTRAINT "auth_lookup_rate_limit_pkey" PRIMARY KEY ("scope", "key", "window_start");



ALTER TABLE ONLY "public"."availability"
    ADD CONSTRAINT "availability_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."avatar_storage_deletions"
    ADD CONSTRAINT "avatar_storage_deletions_bucket_object_path_key" UNIQUE ("bucket", "object_path");



ALTER TABLE ONLY "public"."avatar_storage_deletions"
    ADD CONSTRAINT "avatar_storage_deletions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."base_durations"
    ADD CONSTRAINT "base_durations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_refunds"
    ADD CONSTRAINT "booking_refunds_booking_id_key" UNIQUE ("booking_id");



ALTER TABLE ONLY "public"."booking_refunds"
    ADD CONSTRAINT "booking_refunds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_settings"
    ADD CONSTRAINT "booking_settings_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."booking_timeline"
    ADD CONSTRAINT "booking_timeline_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_application_drafts"
    ADD CONSTRAINT "cleaner_application_drafts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_applications"
    ADD CONSTRAINT "cleaner_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_availability_exceptions"
    ADD CONSTRAINT "cleaner_availability_exceptions_cleaner_id_exception_date_key" UNIQUE ("cleaner_id", "exception_date");



ALTER TABLE ONLY "public"."cleaner_availability_exceptions"
    ADD CONSTRAINT "cleaner_availability_exceptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_data"
    ADD CONSTRAINT "cleaner_data_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."cleaner_devices"
    ADD CONSTRAINT "cleaner_devices_cleaner_id_expo_push_token_key" UNIQUE ("cleaner_id", "expo_push_token");



ALTER TABLE ONLY "public"."cleaner_devices"
    ADD CONSTRAINT "cleaner_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_leads"
    ADD CONSTRAINT "cleaner_leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_schedules"
    ADD CONSTRAINT "cleaner_schedules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_tracking"
    ADD CONSTRAINT "cleaner_tracking_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_upload_link_tokens"
    ADD CONSTRAINT "cleaner_upload_link_tokens_pkey" PRIMARY KEY ("upload_link_id");



ALTER TABLE ONLY "public"."cleaner_upload_links"
    ADD CONSTRAINT "cleaner_upload_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleaner_verifications"
    ADD CONSTRAINT "cleaner_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."co_cleaner_invitations"
    ADD CONSTRAINT "co_cleaner_invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."co_cleaner_invitations"
    ADD CONSTRAINT "co_cleaner_invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."co_cleaner_relationships"
    ADD CONSTRAINT "co_cleaner_relationships_lead_cleaner_id_co_cleaner_id_key" UNIQUE ("lead_cleaner_id", "co_cleaner_id");



ALTER TABLE ONLY "public"."co_cleaner_relationships"
    ADD CONSTRAINT "co_cleaner_relationships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_customer_id_cleaner_id_booking_id_key" UNIQUE ("customer_id", "cleaner_id", "booking_id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deduction_rules"
    ADD CONSTRAINT "deduction_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_signup_tokens"
    ADD CONSTRAINT "email_signup_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_verifications"
    ADD CONSTRAINT "email_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."extra_tasks"
    ADD CONSTRAINT "extra_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback_categories"
    ADD CONSTRAINT "feedback_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."geo_reverse_cache"
    ADD CONSTRAINT "geo_reverse_cache_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."gha_staging"
    ADD CONSTRAINT "gha_staging_pkey" PRIMARY KEY ("gid");



ALTER TABLE ONLY "public"."home_size_durations"
    ADD CONSTRAINT "home_size_durations_pkey" PRIMARY KEY ("home_size");



ALTER TABLE ONLY "public"."inbound_messages"
    ADD CONSTRAINT "inbound_messages_message_sid_key" UNIQUE ("message_sid");



ALTER TABLE ONLY "public"."inbound_messages"
    ADD CONSTRAINT "inbound_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invite_codes"
    ADD CONSTRAINT "invite_codes_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."invite_codes"
    ADD CONSTRAINT "invite_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_offers"
    ADD CONSTRAINT "job_offers_job_id_cleaner_id_key" UNIQUE ("job_id", "cleaner_id");



ALTER TABLE ONLY "public"."job_offers"
    ADD CONSTRAINT "job_offers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_photo_comparisons"
    ADD CONSTRAINT "job_photo_comparisons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kyc_profiles"
    ADD CONSTRAINT "kyc_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kyc_profiles"
    ADD CONSTRAINT "kyc_profiles_sumsub_applicant_id_key" UNIQUE ("sumsub_applicant_id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "no_double_booking" EXCLUDE USING "gist" ("cleaner_id" WITH =, "booking_period" WITH &&) WHERE ((("status" <> 'cancelled'::"public"."booking_status") AND ("cleaner_id" IS NOT NULL)));



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_split_config"
    ADD CONSTRAINT "payment_split_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."payout_methods"
    ADD CONSTRAINT "payout_methods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payout_recipient_audit"
    ADD CONSTRAINT "payout_recipient_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platform_fees"
    ADD CONSTRAINT "platform_fees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platform_settings"
    ADD CONSTRAINT "platform_settings_pkey" PRIMARY KEY ("singleton");



ALTER TABLE ONLY "public"."preferred_cleaner_invitations"
    ADD CONSTRAINT "preferred_cleaner_invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."preferred_cleaner_invitations"
    ADD CONSTRAINT "preferred_cleaner_invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."preferred_cleaners"
    ADD CONSTRAINT "preferred_cleaners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."preferred_cleaners"
    ADD CONSTRAINT "preferred_cleaners_user_id_cleaner_id_key" UNIQUE ("user_id", "cleaner_id");



ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_pricing_version_key" UNIQUE ("pricing_version");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."psk_transaction"
    ADD CONSTRAINT "psk_transaction_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."psk_transaction"
    ADD CONSTRAINT "psk_transaction_reference_key" UNIQUE ("reference");



ALTER TABLE ONLY "public"."reviewer_permissions"
    ADD CONSTRAINT "reviewer_permissions_pkey" PRIMARY KEY ("user_id", "permission_key");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_duration_options"
    ADD CONSTRAINT "service_duration_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_types"
    ADD CONSTRAINT "service_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."testimonials"
    ADD CONSTRAINT "testimonials_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timezones"
    ADD CONSTRAINT "timezones_pkey" PRIMARY KEY ("gid");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_reference_key" UNIQUE ("reference");



ALTER TABLE ONLY "public"."user_login_sessions"
    ADD CONSTRAINT "user_login_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("user_id", "role_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_phone_unique" UNIQUE ("phone");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wallet_deductions"
    ADD CONSTRAINT "wallet_deductions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wallet_transactions"
    ADD CONSTRAINT "wallet_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wallets"
    ADD CONSTRAINT "wallets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wallets"
    ADD CONSTRAINT "wallets_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."whatsapp_inbox_messages"
    ADD CONSTRAINT "whatsapp_inbox_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."withdrawal_requests"
    ADD CONSTRAINT "withdrawal_requests_paystack_reference_key" UNIQUE ("paystack_reference");



ALTER TABLE ONLY "public"."withdrawal_requests"
    ADD CONSTRAINT "withdrawal_requests_paystack_transfer_code_key" UNIQUE ("paystack_transfer_code");



ALTER TABLE ONLY "public"."withdrawal_requests"
    ADD CONSTRAINT "withdrawal_requests_pkey" PRIMARY KEY ("id");



CREATE INDEX "account_merges_merged_at_idx" ON "public"."account_merges" USING "btree" ("merged_at" DESC);



CREATE INDEX "account_merges_primary_user_id_idx" ON "public"."account_merges" USING "btree" ("primary_user_id");



CREATE INDEX "account_merges_secondary_user_id_idx" ON "public"."account_merges" USING "btree" ("secondary_user_id");



CREATE INDEX "auth_identity_lookup_email_normalized_idx" ON "public"."auth_identity_lookup" USING "btree" ("email_normalized");



CREATE INDEX "auth_identity_lookup_phone_e164_idx" ON "public"."auth_identity_lookup" USING "btree" ("phone_e164");



CREATE INDEX "auth_identity_lookup_phone_variants_idx" ON "public"."auth_identity_lookup" USING "gin" ("phone_variants");



CREATE INDEX "auth_identity_lookup_providers_idx" ON "public"."auth_identity_lookup" USING "gin" ("providers");



CREATE INDEX "auth_lookup_rate_limit_window_idx" ON "public"."auth_lookup_rate_limit" USING "btree" ("window_start");



CREATE INDEX "avatar_storage_deletions_delete_after_idx" ON "public"."avatar_storage_deletions" USING "btree" ("delete_after");



CREATE INDEX "bookings_cleaner_hold_expires_at_idx" ON "public"."bookings" USING "btree" ("cleaner_hold_expires_at") WHERE ("cleaner_hold_expires_at" IS NOT NULL);



CREATE UNIQUE INDEX "bookings_customer_idempotency_key_uidx" ON "public"."bookings" USING "btree" ("customer_id", "idempotency_key") WHERE ("idempotency_key" IS NOT NULL);



CREATE INDEX "bookings_location_idx" ON "public"."bookings" USING "gist" ("location_coordinates");



CREATE INDEX "bookings_ops_confirmed_reminder_idx" ON "public"."bookings" USING "btree" ("created_at") WHERE (("status" = 'confirmed'::"public"."booking_status") AND ("payment_status" = 'paid'::"text") AND ("ops_confirmed_reminder_sent_at" IS NULL));



CREATE INDEX "bookings_ops_new_booking_notice_idx" ON "public"."bookings" USING "btree" ("created_at") WHERE ("ops_new_booking_notice_sent_at" IS NULL);



CREATE UNIQUE INDEX "cleaner_application_drafts_user_id_key" ON "public"."cleaner_application_drafts" USING "btree" ("user_id");



CREATE UNIQUE INDEX "cleaner_applications_email_uniq" ON "public"."cleaner_applications" USING "btree" ("lower"(TRIM(BOTH FROM "email"))) WHERE ("email" IS NOT NULL);



CREATE UNIQUE INDEX "cleaner_applications_phone_uniq" ON "public"."cleaner_applications" USING "btree" ("phone");



CREATE UNIQUE INDEX "cleaner_applications_user_id_uniq" ON "public"."cleaner_applications" USING "btree" ("user_id");



CREATE INDEX "cleaner_base_loc_idx" ON "public"."cleaner_data" USING "gist" ("base_location");



CREATE INDEX "cleaner_leads_linked_user_id_idx" ON "public"."cleaner_leads" USING "btree" ("linked_user_id") WHERE ("linked_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "cleaner_leads_phone_uniq" ON "public"."cleaner_leads" USING "btree" ("phone");



CREATE INDEX "cleaner_leads_status_current_step_idx" ON "public"."cleaner_leads" USING "btree" ("status", "current_step");



CREATE UNIQUE INDEX "cleaner_leads_web_continuation_code_key" ON "public"."cleaner_leads" USING "btree" ("web_continuation_code") WHERE ("web_continuation_code" IS NOT NULL);



CREATE UNIQUE INDEX "cleaner_upload_link_tokens_upload_token_uidx" ON "public"."cleaner_upload_link_tokens" USING "btree" ("upload_token");



CREATE UNIQUE INDEX "cleaner_upload_links_active_lead_side_uidx" ON "public"."cleaner_upload_links" USING "btree" ("lead_id", "side") WHERE (("used_at" IS NULL) AND ("revoked_at" IS NULL));



CREATE INDEX "cleaner_upload_links_expires_at_idx" ON "public"."cleaner_upload_links" USING "btree" ("expires_at");



CREATE INDEX "cleaner_upload_links_lead_id_idx" ON "public"."cleaner_upload_links" USING "btree" ("lead_id");



CREATE UNIQUE INDEX "cleaner_upload_links_short_code_uidx" ON "public"."cleaner_upload_links" USING "btree" ("short_code");



CREATE UNIQUE INDEX "co_cleaner_relationships_one_team_per_co_cleaner" ON "public"."co_cleaner_relationships" USING "btree" ("co_cleaner_id");



CREATE INDEX "email_signup_tokens_email_idx" ON "public"."email_signup_tokens" USING "btree" ("email");



CREATE INDEX "email_signup_tokens_expires_at_idx" ON "public"."email_signup_tokens" USING "btree" ("expires_at");



CREATE UNIQUE INDEX "email_signup_tokens_token_hash_idx" ON "public"."email_signup_tokens" USING "btree" ("token_hash");



CREATE INDEX "email_signup_tokens_user_id_idx" ON "public"."email_signup_tokens" USING "btree" ("user_id");



CREATE INDEX "geo_reverse_cache_created_at_idx" ON "public"."geo_reverse_cache" USING "btree" ("created_at");



CREATE INDEX "gha_staging_geom_idx" ON "public"."gha_staging" USING "gist" ("geom");



CREATE INDEX "idx_active_rules" ON "public"."deduction_rules" USING "btree" ("is_active", "start_date") WHERE (("is_active" = true) AND ("end_date" IS NULL));



CREATE INDEX "idx_availability_cleaner_id" ON "public"."availability" USING "btree" ("cleaner_id");



CREATE INDEX "idx_availability_times" ON "public"."availability" USING "btree" ("start_time", "end_time");



CREATE INDEX "idx_booking_refunds_customer_id" ON "public"."booking_refunds" USING "btree" ("customer_id");



CREATE INDEX "idx_booking_refunds_paystack_tx_ref" ON "public"."booking_refunds" USING "btree" ("paystack_transaction_reference") WHERE ("paystack_transaction_reference" IS NOT NULL);



CREATE INDEX "idx_bookings_cleaner" ON "public"."bookings" USING "btree" ("cleaner_id");



CREATE INDEX "idx_bookings_cleaner_customer_status" ON "public"."bookings" USING "btree" ("cleaner_id", "customer_id", "status");



CREATE INDEX "idx_bookings_cleaner_ext" ON "public"."bookings" USING "btree" ("cleaner_id");



CREATE INDEX "idx_bookings_cleaner_id" ON "public"."bookings" USING "btree" ("cleaner_id");



CREATE INDEX "idx_bookings_cleaner_status_customer" ON "public"."bookings" USING "btree" ("cleaner_id", "status", "customer_id");



CREATE INDEX "idx_bookings_cleaner_status_scheduled_at_utc" ON "public"."bookings" USING "btree" ("cleaner_id", "status", "scheduled_at_utc");



CREATE INDEX "idx_bookings_customer" ON "public"."bookings" USING "btree" ("customer_id");



CREATE INDEX "idx_bookings_customer_cleaner_status" ON "public"."bookings" USING "btree" ("customer_id", "cleaner_id", "status");



CREATE INDEX "idx_bookings_customer_ext" ON "public"."bookings" USING "btree" ("customer_id");



CREATE INDEX "idx_bookings_customer_id" ON "public"."bookings" USING "btree" ("customer_id");



CREATE INDEX "idx_bookings_customer_status_scheduled_at_utc" ON "public"."bookings" USING "btree" ("customer_id", "status", "scheduled_at_utc");



CREATE INDEX "idx_bookings_final_amount_minor" ON "public"."bookings" USING "btree" ("final_amount_minor");



CREATE INDEX "idx_bookings_hold_cleanup" ON "public"."bookings" USING "btree" ("payment_status", "status", "created_at") WHERE ("cleaner_id" IS NOT NULL);



CREATE INDEX "idx_bookings_location_gist" ON "public"."bookings" USING "gist" ("location_coordinates");



CREATE INDEX "idx_bookings_pending_holds_cleanup" ON "public"."bookings" USING "btree" ("created_at") WHERE (("cleaner_id" IS NOT NULL) AND ("status" = 'pending'::"public"."booking_status") AND (COALESCE("payment_status", 'pending'::"text") = 'pending'::"text"));



CREATE INDEX "idx_bookings_scheduled_date" ON "public"."bookings" USING "btree" ("scheduled_date" DESC);



CREATE INDEX "idx_bookings_service_duration_option_id" ON "public"."bookings" USING "btree" ("service_duration_option_id") WHERE ("service_duration_option_id" IS NOT NULL);



CREATE INDEX "idx_bookings_status" ON "public"."bookings" USING "btree" ("status");



CREATE INDEX "idx_bookings_subscription_id" ON "public"."bookings" USING "btree" ("subscription_id") WHERE ("subscription_id" IS NOT NULL);



CREATE INDEX "idx_bookings_time_decimal" ON "public"."bookings" USING "btree" ("scheduled_date", "start_time_decimal");



CREATE INDEX "idx_bookings_unpaid_cleaner_hold_15min" ON "public"."bookings" USING "btree" ("cleaner_assigned_at") WHERE (("cleaner_id" IS NOT NULL) AND ("payment_status" IS DISTINCT FROM 'paid'::"text"));



CREATE INDEX "idx_cleaner_application_drafts_updated_at_desc" ON "public"."cleaner_application_drafts" USING "btree" ("updated_at" DESC NULLS LAST);



COMMENT ON INDEX "public"."idx_cleaner_application_drafts_updated_at_desc" IS 'Supports draft lists ordered by updated_at descending.';



CREATE INDEX "idx_cleaner_applications_created_at_desc" ON "public"."cleaner_applications" USING "btree" ("created_at" DESC NULLS LAST);



COMMENT ON INDEX "public"."idx_cleaner_applications_created_at_desc" IS 'Supports admin list sorted by created_at descending.';



CREATE INDEX "idx_cleaner_applications_user_id" ON "public"."cleaner_applications" USING "btree" ("user_id");



CREATE INDEX "idx_cleaner_availability_exceptions_cleaner_date" ON "public"."cleaner_availability_exceptions" USING "btree" ("cleaner_id", "exception_date");



CREATE INDEX "idx_cleaner_availability_exceptions_cleaner_id" ON "public"."cleaner_availability_exceptions" USING "btree" ("cleaner_id");



CREATE INDEX "idx_cleaner_availability_exceptions_date" ON "public"."cleaner_availability_exceptions" USING "btree" ("exception_date");



CREATE INDEX "idx_cleaner_base_loc_gist" ON "public"."cleaner_data" USING "gist" ("base_location");



CREATE INDEX "idx_cleaner_base_location_gist" ON "public"."cleaner_data" USING "gist" ("base_location");



CREATE INDEX "idx_cleaner_data_active_updated_at_desc" ON "public"."cleaner_data" USING "btree" ("updated_at" DESC NULLS LAST) WHERE ("status" = 'active'::"public"."cleaner_status");



COMMENT ON INDEX "public"."idx_cleaner_data_active_updated_at_desc" IS 'Partial index for active cleaners sorted by updated_at (admin active roster).';



CREATE INDEX "idx_cleaner_data_user" ON "public"."cleaner_data" USING "btree" ("user_id");



CREATE INDEX "idx_cleaner_data_user_id" ON "public"."cleaner_data" USING "btree" ("user_id");



CREATE INDEX "idx_cleaner_data_user_status" ON "public"."cleaner_data" USING "btree" ("user_id", "status");



CREATE INDEX "idx_cleaner_devices_cleaner_id" ON "public"."cleaner_devices" USING "btree" ("cleaner_id");



CREATE INDEX "idx_cleaner_paystack_id" ON "public"."cleaner_data" USING "btree" ("paystack_customer_id");



CREATE INDEX "idx_cleaner_schedules_cleaner_id" ON "public"."cleaner_schedules" USING "btree" ("cleaner_id");



CREATE INDEX "idx_cleaner_tracking_booking_created" ON "public"."cleaner_tracking" USING "btree" ("booking_id", "created_at" DESC);



CREATE INDEX "idx_cleaner_tracking_booking_id" ON "public"."cleaner_tracking" USING "btree" ("booking_id");



CREATE INDEX "idx_cleaner_verifications_id" ON "public"."cleaner_verifications" USING "btree" ("id");



CREATE INDEX "idx_co_cleaner_invitations_inviter" ON "public"."co_cleaner_invitations" USING "btree" ("inviter_user_id");



CREATE INDEX "idx_co_cleaner_invitations_token_pending" ON "public"."co_cleaner_invitations" USING "btree" ("token") WHERE ("status" = 'pending'::"text");



CREATE INDEX "idx_co_cleaner_relationships_co" ON "public"."co_cleaner_relationships" USING "btree" ("co_cleaner_id");



CREATE INDEX "idx_co_cleaner_relationships_lead" ON "public"."co_cleaner_relationships" USING "btree" ("lead_cleaner_id");



CREATE INDEX "idx_conversations_booking_id" ON "public"."conversations" USING "btree" ("booking_id");



CREATE INDEX "idx_conversations_last_msg" ON "public"."conversations" USING "btree" ("last_message_at" DESC);



CREATE INDEX "idx_conversations_participants" ON "public"."conversations" USING "btree" ("customer_id", "cleaner_id");



CREATE INDEX "idx_device_tokens_platform" ON "public"."device_tokens" USING "btree" ("platform");



CREATE INDEX "idx_device_tokens_user_id" ON "public"."device_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_discounts_active_service" ON "public"."discounts" USING "btree" ("service_type_id") WHERE ("active" = true);



CREATE INDEX "idx_feedback_cleaner_id" ON "public"."feedback" USING "btree" ("cleaner_id");



CREATE INDEX "idx_feedback_customer_id" ON "public"."feedback" USING "btree" ("customer_id");



CREATE INDEX "idx_invite_codes_user_role" ON "public"."invite_codes" USING "btree" ("user_role");



CREATE INDEX "idx_job_offers_cleaner_id" ON "public"."job_offers" USING "btree" ("cleaner_id");



CREATE INDEX "idx_job_offers_cleaner_status" ON "public"."job_offers" USING "btree" ("cleaner_id", "status");



CREATE INDEX "idx_job_offers_job_id" ON "public"."job_offers" USING "btree" ("job_id");



CREATE INDEX "idx_job_photo_comparisons_booking_id" ON "public"."job_photo_comparisons" USING "btree" ("booking_id");



CREATE INDEX "idx_jobs_claimed_by" ON "public"."jobs" USING "btree" ("claimed_by");



CREATE INDEX "idx_jobs_customer_id" ON "public"."jobs" USING "btree" ("customer_id");



CREATE INDEX "idx_jobs_requested_at" ON "public"."jobs" USING "btree" ("requested_at" DESC);



CREATE INDEX "idx_jobs_status" ON "public"."jobs" USING "btree" ("status");



CREATE INDEX "idx_messages_conv_id" ON "public"."messages" USING "btree" ("conversation_id", "created_at" DESC);



CREATE INDEX "idx_messages_sender_id" ON "public"."messages" USING "btree" ("sender_id");



CREATE INDEX "idx_messages_unread" ON "public"."messages" USING "btree" ("conversation_id") WHERE ("read_at" IS NULL);



CREATE INDEX "idx_notifications_read_status" ON "public"."notifications" USING "btree" ("read") WHERE ("read" = false);



CREATE INDEX "idx_notifications_user_id" ON "public"."notifications" USING "btree" ("user_id");



CREATE INDEX "idx_notifications_user_id_created" ON "public"."notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "idx_one_active_rule_per_name" ON "public"."deduction_rules" USING "btree" ("name") WHERE ("is_active" = true);



CREATE UNIQUE INDEX "idx_one_default_per_user" ON "public"."payout_methods" USING "btree" ("user_id") WHERE ("is_default" = true);



CREATE INDEX "idx_payout_methods_user_id" ON "public"."payout_methods" USING "btree" ("user_id");



CREATE INDEX "idx_platform_fees_is_default" ON "public"."platform_fees" USING "btree" ("is_default");



CREATE UNIQUE INDEX "idx_platform_fees_unique_default" ON "public"."platform_fees" USING "btree" ("is_default") WHERE ("is_default" = true);



CREATE INDEX "idx_preferred_cleaner_invitations_inviter" ON "public"."preferred_cleaner_invitations" USING "btree" ("inviter_user_id");



CREATE INDEX "idx_preferred_cleaner_invitations_token_pending" ON "public"."preferred_cleaner_invitations" USING "btree" ("token") WHERE ("status" = 'pending'::"text");



CREATE INDEX "idx_preferred_cleaners_user_id" ON "public"."preferred_cleaners" USING "btree" ("user_id");



CREATE INDEX "idx_pricing_rules_effective_window" ON "public"."pricing_rules" USING "btree" ("effective_from", "effective_to");



CREATE UNIQUE INDEX "idx_pricing_rules_single_active" ON "public"."pricing_rules" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_profiles_deletion_scheduled_for" ON "public"."profiles" USING "btree" ("deletion_scheduled_for") WHERE ("deletion_status" = 'scheduled'::"text");



CREATE INDEX "idx_profiles_deletion_status" ON "public"."profiles" USING "btree" ("deletion_status");



CREATE INDEX "idx_profiles_id" ON "public"."profiles" USING "btree" ("id");



CREATE INDEX "idx_profiles_location_wkt" ON "public"."profiles" USING "gist" ("location_wkt");



CREATE INDEX "idx_psk_booking" ON "public"."psk_transaction" USING "btree" ("booking_id");



CREATE INDEX "idx_psk_ref" ON "public"."psk_transaction" USING "btree" ("reference");



CREATE INDEX "idx_reviewer_permissions_user_id" ON "public"."reviewer_permissions" USING "btree" ("user_id");



CREATE INDEX "idx_reviews_booking_id" ON "public"."reviews" USING "btree" ("booking_id");



CREATE INDEX "idx_reviews_reviewee_created" ON "public"."reviews" USING "btree" ("reviewee_id", "created_at" DESC);



CREATE INDEX "idx_reviews_reviewee_id" ON "public"."reviews" USING "btree" ("reviewee_id");



CREATE INDEX "idx_service_duration_options_service" ON "public"."service_duration_options" USING "btree" ("service_type_id");



CREATE INDEX "idx_service_types_category_id" ON "public"."service_types" USING "btree" ("category_id");



CREATE INDEX "idx_subscriptions_customer" ON "public"."subscriptions" USING "btree" ("customer_id");



CREATE INDEX "idx_subscriptions_paystack_code" ON "public"."subscriptions" USING "btree" ("paystack_subscription_code") WHERE ("paystack_subscription_code" IS NOT NULL);



CREATE INDEX "idx_subscriptions_recurring_amount_minor" ON "public"."subscriptions" USING "btree" ("recurring_amount_minor");



CREATE INDEX "idx_subscriptions_status" ON "public"."subscriptions" USING "btree" ("status");



CREATE INDEX "idx_testimonials_created_at" ON "public"."testimonials" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_transactions_user_id_status" ON "public"."transactions" USING "btree" ("cleaner_id", "status");



CREATE INDEX "idx_user_roles_role_id" ON "public"."user_roles" USING "btree" ("role_id");



CREATE INDEX "idx_user_roles_role_id_user_id" ON "public"."user_roles" USING "btree" ("role_id", "user_id");



COMMENT ON INDEX "public"."idx_user_roles_role_id_user_id" IS 'Speeds admin roster: fetch all user_ids where role_id = cleaner.';



CREATE INDEX "idx_user_roles_user_role" ON "public"."user_roles" USING "btree" ("user_id", "role_id");



CREATE INDEX "idx_users_id" ON "public"."users" USING "btree" ("id");



CREATE INDEX "idx_wallet_deductions_created_at" ON "public"."wallet_deductions" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "idx_wallet_deductions_transaction_rule" ON "public"."wallet_deductions" USING "btree" ("transaction_id", "rule_id");



CREATE INDEX "idx_wallet_deductions_user_id" ON "public"."wallet_deductions" USING "btree" ("user_id");



CREATE INDEX "idx_wallet_transactions_booking_id" ON "public"."wallet_transactions" USING "btree" ("booking_id");



CREATE INDEX "idx_wallet_transactions_created_at" ON "public"."wallet_transactions" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_wallet_transactions_wallet_id" ON "public"."wallet_transactions" USING "btree" ("wallet_id");



CREATE INDEX "idx_wallets_user_id" ON "public"."wallets" USING "btree" ("user_id");



CREATE INDEX "idx_whatsapp_inbox_messages_phone_created_at" ON "public"."whatsapp_inbox_messages" USING "btree" ("phone_e164", "created_at");



CREATE INDEX "idx_whatsapp_inbox_messages_twilio_sid" ON "public"."whatsapp_inbox_messages" USING "btree" ("twilio_message_sid");



CREATE INDEX "idx_whatsapp_inbox_messages_user_id" ON "public"."whatsapp_inbox_messages" USING "btree" ("user_id");



CREATE INDEX "idx_withdrawal_pending" ON "public"."withdrawal_requests" USING "btree" ("status") WHERE ("status" = 'pending'::"public"."withdrawal_status");



CREATE INDEX "idx_withdrawal_requests_cleaner_id" ON "public"."withdrawal_requests" USING "btree" ("cleaner_id");



CREATE INDEX "inbound_messages_created_at_idx" ON "public"."inbound_messages" USING "btree" ("created_at");



CREATE INDEX "inbound_messages_from_idx" ON "public"."inbound_messages" USING "btree" ("from");



CREATE INDEX "inbound_messages_to_idx" ON "public"."inbound_messages" USING "btree" ("to");



CREATE INDEX "invite_codes_code_idx" ON "public"."invite_codes" USING "btree" ("code");



CREATE INDEX "invite_codes_enabled_idx" ON "public"."invite_codes" USING "btree" ("enabled");



CREATE INDEX "kyc_profiles_cleaner_application_id_idx" ON "public"."kyc_profiles" USING "btree" ("cleaner_application_id");



CREATE INDEX "kyc_profiles_sumsub_applicant_id_idx" ON "public"."kyc_profiles" USING "btree" ("sumsub_applicant_id");



CREATE INDEX "kyc_profiles_user_id_idx" ON "public"."kyc_profiles" USING "btree" ("user_id");



CREATE UNIQUE INDEX "one_default_payout_method_per_user" ON "public"."payout_methods" USING "btree" ("user_id") WHERE ("is_default" IS TRUE);



COMMENT ON INDEX "public"."one_default_payout_method_per_user" IS 'At most one payout_methods row per user may have is_default TRUE. Fix duplicate defaults before applying if migration fails.';



CREATE UNIQUE INDEX "payout_methods_one_default_per_user_purpose" ON "public"."payout_methods" USING "btree" ("user_id", "purpose") WHERE ("is_default" IS TRUE);



CREATE UNIQUE INDEX "payout_methods_user_purpose_account_unique" ON "public"."payout_methods" USING "btree" ("user_id", "purpose", "type", "account_number", COALESCE("bank_code", ''::"text"));



CREATE INDEX "payout_recipient_audit_recipient_code_idx" ON "public"."payout_recipient_audit" USING "btree" ("recipient_code") WHERE ("recipient_code" IS NOT NULL);



CREATE INDEX "payout_recipient_audit_user_id_created_at_idx" ON "public"."payout_recipient_audit" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "profiles_user_id_key" ON "public"."profiles" USING "btree" ("user_id");



CREATE UNIQUE INDEX "reviews_booking_id_key" ON "public"."reviews" USING "btree" ("booking_id") WHERE ("booking_id" IS NOT NULL);



CREATE INDEX "timezones_geom_idx" ON "public"."timezones" USING "gist" ("geom");



CREATE INDEX "user_login_sessions_created_at_idx" ON "public"."user_login_sessions" USING "btree" ("created_at" DESC);



CREATE INDEX "user_login_sessions_user_id_idx" ON "public"."user_login_sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "users_phone_unique_idx" ON "public"."users" USING "btree" ("phone") WHERE ("phone" IS NOT NULL);



CREATE OR REPLACE TRIGGER "bookings_compute_scheduled_at_utc" BEFORE INSERT OR UPDATE OF "scheduled_date", "scheduled_time", "timezone_name" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."compute_booking_scheduled_at_utc"();



CREATE OR REPLACE TRIGGER "bookings_guard_payment_status" BEFORE UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."guard_booking_payment_status_writes"();



CREATE OR REPLACE TRIGGER "ensure_single_default_platform_fee_trigger" BEFORE INSERT OR UPDATE ON "public"."platform_fees" FOR EACH ROW WHEN (("new"."is_default" = true)) EXECUTE FUNCTION "public"."ensure_single_default_platform_fee"();



CREATE OR REPLACE TRIGGER "geo_reverse_cache_set_updated_at" BEFORE UPDATE ON "public"."geo_reverse_cache" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "on_booking_completed" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."handle_job_completion"();



CREATE OR REPLACE TRIGGER "payout_methods_touch_updated_at" BEFORE UPDATE ON "public"."payout_methods" FOR EACH ROW EXECUTE FUNCTION "public"."touch_payout_methods_updated_at"();



CREATE OR REPLACE TRIGGER "tr_log_booking_status_change" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."fn_log_status_change"();



CREATE OR REPLACE TRIGGER "tr_on_cleaner_created" AFTER INSERT ON "public"."cleaner_data" FOR EACH ROW EXECUTE FUNCTION "public"."fn_create_wallet_for_new_cleaner"();



CREATE OR REPLACE TRIGGER "trg_booking_refunds_updated_at" BEFORE UPDATE ON "public"."booking_refunds" FOR EACH ROW EXECUTE FUNCTION "public"."touch_booking_refunds_updated_at"();



CREATE OR REPLACE TRIGGER "trg_bookings_guard_payment_status" BEFORE UPDATE OF "payment_status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."bookings_guard_payment_status"();



CREATE OR REPLACE TRIGGER "trg_profiles_fullname" BEFORE INSERT OR UPDATE OF "firstname", "lastname" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."fn_sync_profile_fullname"();



CREATE OR REPLACE TRIGGER "trg_set_cleaner_assigned_at_for_hold" BEFORE INSERT OR UPDATE OF "cleaner_id", "payment_status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_cleaner_assigned_at_for_hold"();



CREATE OR REPLACE TRIGGER "trigger_calculate_booking_period" BEFORE INSERT OR UPDATE OF "scheduled_date", "scheduled_time", "duration_hours", "timezone" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."calculate_booking_period"();



CREATE OR REPLACE TRIGGER "trigger_set_booking_timezone" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_booking_timezone"();



CREATE OR REPLACE TRIGGER "trigger_sync_convo_time" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_conversation_timestamp"();



CREATE OR REPLACE TRIGGER "trigger_update_cleaner_availability_exceptions_updated_at" BEFORE UPDATE ON "public"."cleaner_availability_exceptions" FOR EACH ROW EXECUTE FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"();



CREATE OR REPLACE TRIGGER "update_platform_fees_updated_at" BEFORE UPDATE ON "public"."platform_fees" FOR EACH ROW EXECUTE FUNCTION "public"."update_platform_fees_updated_at"();



ALTER TABLE ONLY "public"."auth_identity_lookup"
    ADD CONSTRAINT "auth_identity_lookup_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."availability"
    ADD CONSTRAINT "availability_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."avatar_storage_deletions"
    ADD CONSTRAINT "avatar_storage_deletions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_refunds"
    ADD CONSTRAINT "booking_refunds_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_refunds"
    ADD CONSTRAINT "booking_refunds_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_timeline"
    ADD CONSTRAINT "booking_timeline_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_cancelled_by_fkey" FOREIGN KEY ("cancelled_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_service_duration_option_id_fkey" FOREIGN KEY ("service_duration_option_id") REFERENCES "public"."service_duration_options"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "public"."service_types"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cleaner_application_drafts"
    ADD CONSTRAINT "cleaner_application_drafts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_applications"
    ADD CONSTRAINT "cleaner_applications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_availability_exceptions"
    ADD CONSTRAINT "cleaner_availability_exceptions_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_data"
    ADD CONSTRAINT "cleaner_data_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_devices"
    ADD CONSTRAINT "cleaner_devices_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_leads"
    ADD CONSTRAINT "cleaner_leads_linked_user_id_fkey" FOREIGN KEY ("linked_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cleaner_schedules"
    ADD CONSTRAINT "cleaner_schedules_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_tracking"
    ADD CONSTRAINT "cleaner_tracking_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_tracking"
    ADD CONSTRAINT "cleaner_tracking_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_upload_link_tokens"
    ADD CONSTRAINT "cleaner_upload_link_tokens_upload_link_id_fkey" FOREIGN KEY ("upload_link_id") REFERENCES "public"."cleaner_upload_links"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_upload_links"
    ADD CONSTRAINT "cleaner_upload_links_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."cleaner_leads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cleaner_verifications"
    ADD CONSTRAINT "cleaner_verifications_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."co_cleaner_invitations"
    ADD CONSTRAINT "co_cleaner_invitations_accepted_user_id_fkey" FOREIGN KEY ("accepted_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."co_cleaner_invitations"
    ADD CONSTRAINT "co_cleaner_invitations_inviter_user_id_fkey" FOREIGN KEY ("inviter_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."co_cleaner_relationships"
    ADD CONSTRAINT "co_cleaner_relationships_co_cleaner_id_fkey" FOREIGN KEY ("co_cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."co_cleaner_relationships"
    ADD CONSTRAINT "co_cleaner_relationships_lead_cleaner_id_fkey" FOREIGN KEY ("lead_cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_service_type_id_fkey" FOREIGN KEY ("service_type_id") REFERENCES "public"."service_types"("id");



ALTER TABLE ONLY "public"."email_signup_tokens"
    ADD CONSTRAINT "email_signup_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."cleaner_data"("user_id");



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."job_offers"
    ADD CONSTRAINT "job_offers_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_offers"
    ADD CONSTRAINT "job_offers_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_photo_comparisons"
    ADD CONSTRAINT "job_photo_comparisons_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_claimed_by_fkey" FOREIGN KEY ("claimed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kyc_profiles"
    ADD CONSTRAINT "kyc_profiles_cleaner_application_id_fkey" FOREIGN KEY ("cleaner_application_id") REFERENCES "public"."cleaner_applications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kyc_profiles"
    ADD CONSTRAINT "kyc_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payout_methods"
    ADD CONSTRAINT "payout_methods_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payout_recipient_audit"
    ADD CONSTRAINT "payout_recipient_audit_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."platform_fees"
    ADD CONSTRAINT "platform_fees_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."platform_settings"
    ADD CONSTRAINT "platform_settings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."preferred_cleaner_invitations"
    ADD CONSTRAINT "preferred_cleaner_invitations_accepted_cleaner_id_fkey" FOREIGN KEY ("accepted_cleaner_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."preferred_cleaner_invitations"
    ADD CONSTRAINT "preferred_cleaner_invitations_inviter_user_id_fkey" FOREIGN KEY ("inviter_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."preferred_cleaners"
    ADD CONSTRAINT "preferred_cleaners_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."cleaner_data"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."preferred_cleaners"
    ADD CONSTRAINT "preferred_cleaners_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."psk_transaction"
    ADD CONSTRAINT "psk_transaction_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."psk_transaction"
    ADD CONSTRAINT "psk_transaction_user_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviewer_permissions"
    ADD CONSTRAINT "reviewer_permissions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_reviewee_id_fkey" FOREIGN KEY ("reviewee_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_reviewer_id_fkey" FOREIGN KEY ("reviewer_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_duration_options"
    ADD CONSTRAINT "service_duration_options_service_type_id_fkey" FOREIGN KEY ("service_type_id") REFERENCES "public"."service_types"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_types"
    ADD CONSTRAINT "service_types_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."service_categories"("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."cleaner_data"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "public"."service_types"("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_login_sessions"
    ADD CONSTRAINT "user_login_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wallet_deductions"
    ADD CONSTRAINT "wallet_deductions_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "public"."deduction_rules"("id");



ALTER TABLE ONLY "public"."wallet_deductions"
    ADD CONSTRAINT "wallet_deductions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "wallet_transactions_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wallet_transactions"
    ADD CONSTRAINT "wallet_transactions_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wallet_transactions"
    ADD CONSTRAINT "wallet_transactions_wallet_id_fkey" FOREIGN KEY ("wallet_id") REFERENCES "public"."wallets"("id");



ALTER TABLE ONLY "public"."wallets"
    ADD CONSTRAINT "wallets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."whatsapp_inbox_messages"
    ADD CONSTRAINT "whatsapp_inbox_messages_sent_by_user_id_fkey" FOREIGN KEY ("sent_by_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."whatsapp_inbox_messages"
    ADD CONSTRAINT "whatsapp_inbox_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."withdrawal_requests"
    ADD CONSTRAINT "withdrawal_requests_cleaner_id_fkey" FOREIGN KEY ("cleaner_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."withdrawal_requests"
    ADD CONSTRAINT "withdrawal_requests_wallet_id_fkey" FOREIGN KEY ("wallet_id") REFERENCES "public"."wallets"("id");



CREATE POLICY "Admin delete pricing_rules" ON "public"."pricing_rules" FOR DELETE TO "authenticated" USING ((("auth"."jwt"() ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "Admin update pricing_rules" ON "public"."pricing_rules" FOR UPDATE TO "authenticated" USING ((("auth"."jwt"() ->> 'role'::"text") = 'admin'::"text")) WITH CHECK ((("auth"."jwt"() ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "Admins can delete cleaner leads" ON "public"."cleaner_leads" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = "auth"."uid"()) AND ("ur"."role_id" = 'admin'::"text")))));



CREATE POLICY "Admins can delete platform fees" ON "public"."platform_fees" FOR DELETE USING ("public"."is_platform_fee_admin"());



CREATE POLICY "Admins can insert platform fees" ON "public"."platform_fees" FOR INSERT WITH CHECK ("public"."is_platform_fee_admin"());



CREATE POLICY "Admins can select platform fees" ON "public"."platform_fees" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role_id" = 'admin'::"text")))));



CREATE POLICY "Admins can update cleaner leads" ON "public"."cleaner_leads" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = "auth"."uid"()) AND ("ur"."role_id" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = "auth"."uid"()) AND ("ur"."role_id" = 'admin'::"text")))));



CREATE POLICY "Admins can update platform fees" ON "public"."platform_fees" FOR UPDATE USING ("public"."is_platform_fee_admin"()) WITH CHECK ("public"."is_platform_fee_admin"());



CREATE POLICY "Admins can view all user roles (safe)" ON "public"."user_roles" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "Admins can view cleaner leads" ON "public"."cleaner_leads" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = "auth"."uid"()) AND ("ur"."role_id" = 'admin'::"text")))));



CREATE POLICY "Admins can view platform fees" ON "public"."platform_fees" FOR SELECT USING ("public"."is_platform_fee_admin"());



CREATE POLICY "Allow public read access" ON "public"."base_durations" FOR SELECT USING (true);



CREATE POLICY "Allow public read access" ON "public"."extra_tasks" FOR SELECT USING (true);



CREATE POLICY "Allow read for authenticated" ON "public"."payment_split_config" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow read for service role" ON "public"."payment_split_config" FOR SELECT TO "service_role" USING (true);



CREATE POLICY "Authenticated users can insert cleaner leads" ON "public"."cleaner_leads" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Cleaner or customer can read own bookings" ON "public"."bookings" FOR SELECT TO "authenticated" USING ((("cleaner_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("customer_id" = ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "Cleaners can delete their own availability exceptions" ON "public"."cleaner_availability_exceptions" FOR DELETE USING (("auth"."uid"() = "cleaner_id"));



CREATE POLICY "Cleaners can insert their own availability exceptions" ON "public"."cleaner_availability_exceptions" FOR INSERT WITH CHECK (("auth"."uid"() = "cleaner_id"));



CREATE POLICY "Cleaners can update their own availability exceptions" ON "public"."cleaner_availability_exceptions" FOR UPDATE USING (("auth"."uid"() = "cleaner_id")) WITH CHECK (("auth"."uid"() = "cleaner_id"));



CREATE POLICY "Cleaners can view their own availability exceptions" ON "public"."cleaner_availability_exceptions" FOR SELECT USING (("auth"."uid"() = "cleaner_id"));



CREATE POLICY "Customers and cleaners can view platform fees" ON "public"."platform_fees" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role_id" = ANY (ARRAY['customer'::"text", 'cleaner'::"text"]))))) OR (EXISTS ( SELECT 1
   FROM "public"."user_roles" "ur"
  WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role_id" = 'admin'::"text"))))));



CREATE POLICY "Customers can insert own subscriptions" ON "public"."subscriptions" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can read own subscriptions" ON "public"."subscriptions" FOR SELECT USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Everyone can view testimonials" ON "public"."testimonials" FOR SELECT USING (true);



CREATE POLICY "Insert_Own_Conversations" ON "public"."conversations" FOR INSERT WITH CHECK ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id")));



CREATE POLICY "Profiles are viewable by everyone" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Public profiles are viewable" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "id") OR (("deleted_at" IS NULL) AND ("deactivated_at" IS NULL) AND ("deletion_status" <> ALL (ARRAY['scheduled'::"text", 'processing'::"text", 'completed'::"text"])))));



COMMENT ON POLICY "Public profiles are viewable" ON "public"."profiles" IS 'Owners always read their row; others skip deactivated, legacy-deleted, or deletion pipeline rows.';



CREATE POLICY "Public read pricing_rules" ON "public"."pricing_rules" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Send_Messages_In_Joined_Convos" ON "public"."messages" FOR INSERT WITH CHECK ((("sender_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."conversations"
  WHERE (("conversations"."id" = "messages"."conversation_id") AND (("conversations"."customer_id" = "auth"."uid"()) OR ("conversations"."cleaner_id" = "auth"."uid"())))))));



CREATE POLICY "Service role full access on avatar_storage_deletions" ON "public"."avatar_storage_deletions" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access on payout_recipient_audit" ON "public"."payout_recipient_audit" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "System can view all availability exceptions" ON "public"."cleaner_availability_exceptions" FOR SELECT USING (true);



CREATE POLICY "Users can delete own preferred cleaners" ON "public"."preferred_cleaners" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own preferred cleaners" ON "public"."preferred_cleaners" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read own preferred cleaners" ON "public"."preferred_cleaners" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read their own kyc" ON "public"."kyc_profiles" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view data through bookings" ON "public"."users" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "id") OR (EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."cleaner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("b"."customer_id" = "users"."id") AND ("b"."status" IS DISTINCT FROM 'cancelled'::"public"."booking_status")))) OR ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."customer_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("b"."cleaner_id" = "users"."id") AND ("b"."status" IS DISTINCT FROM 'cancelled'::"public"."booking_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."cleaner_data" "cd"
  WHERE ("cd"."user_id" = "users"."id"))))));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view related user data via helper" ON "public"."users" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "id") OR "public"."can_view_user_via_bookings"("id")));



CREATE POLICY "Users can view their own roles" ON "public"."user_roles" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users delete own device tokens" ON "public"."device_tokens" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users insert own device tokens" ON "public"."device_tokens" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users manage own device tokens" ON "public"."device_tokens" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users queue own avatar deletions" ON "public"."avatar_storage_deletions" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bucket" = 'avatars'::"text") AND ("object_path" ~~ ((( SELECT "auth"."uid"() AS "uid"))::"text" || '/%'::"text"))));



CREATE POLICY "Users read own avatar deletions" ON "public"."avatar_storage_deletions" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bucket" = 'avatars'::"text") AND ("object_path" ~~ ((( SELECT "auth"."uid"() AS "uid"))::"text" || '/%'::"text"))));



CREATE POLICY "Users read own device tokens" ON "public"."device_tokens" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users update own avatar deletions" ON "public"."avatar_storage_deletions" FOR UPDATE TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bucket" = 'avatars'::"text") AND ("object_path" ~~ ((( SELECT "auth"."uid"() AS "uid"))::"text" || '/%'::"text")))) WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bucket" = 'avatars'::"text") AND ("object_path" ~~ ((( SELECT "auth"."uid"() AS "uid"))::"text" || '/%'::"text"))));



CREATE POLICY "Users update own device tokens" ON "public"."device_tokens" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users update own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users view via bookings" ON "public"."users" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "id") OR "public"."can_view_user_via_bookings"("id")));



CREATE POLICY "View_Messages_In_Joined_Convos" ON "public"."messages" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."conversations"
  WHERE (("conversations"."id" = "messages"."conversation_id") AND (("conversations"."customer_id" = "auth"."uid"()) OR ("conversations"."cleaner_id" = "auth"."uid"()))))));



CREATE POLICY "View_Own_Conversations" ON "public"."conversations" FOR SELECT USING ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id")));



ALTER TABLE "public"."account_merges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admins_all_booking_settings" ON "public"."booking_settings" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_booking_timeline" ON "public"."booking_timeline" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_cleaner_applications" ON "public"."cleaner_applications" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_cleaner_data" ON "public"."cleaner_data" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_cleaner_verifications" ON "public"."cleaner_verifications" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_deduction_rules" ON "public"."deduction_rules" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_device_tokens" ON "public"."device_tokens" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_discounts" ON "public"."discounts" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_feedback" ON "public"."feedback" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_feedback_categories" ON "public"."feedback_categories" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_home_size_durations" ON "public"."home_size_durations" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_invite_codes" ON "public"."invite_codes" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_notifications" ON "public"."notifications" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_payout_methods" ON "public"."payout_methods" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_reviews" ON "public"."reviews" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_roles" ON "public"."roles" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_service_categories" ON "public"."service_categories" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_service_types" ON "public"."service_types" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_transactions" ON "public"."transactions" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_wallet_deductions" ON "public"."wallet_deductions" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_wallet_transactions" ON "public"."wallet_transactions" TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_wallets" ON "public"."wallets" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_all_withdrawal_requests" ON "public"."withdrawal_requests" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_manage_user_roles" ON "public"."user_roles" TO "authenticated" USING ("public"."has_role"('admin'::"text")) WITH CHECK ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_select_profiles" ON "public"."profiles" FOR SELECT TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_select_users" ON "public"."users" FOR SELECT TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "admins_update_profiles" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ("public"."has_role"('admin'::"text"));



CREATE POLICY "allow_insert_own_user" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "allow_insert_own_user" ON "public"."users" FOR INSERT TO "authenticated" WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "allow_insert_profiles" ON "public"."profiles" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);



CREATE POLICY "allow_insert_users" ON "public"."users" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);



CREATE POLICY "anon_read_booking_settings" ON "public"."booking_settings" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_discounts" ON "public"."discounts" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_feedback_categories" ON "public"."feedback_categories" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_home_size_durations" ON "public"."home_size_durations" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_invite_codes" ON "public"."invite_codes" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_service_categories" ON "public"."service_categories" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_service_types" ON "public"."service_types" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anyone_read_booking_settings" ON "public"."booking_settings" FOR SELECT USING (true);



CREATE POLICY "anyone_read_discounts" ON "public"."discounts" FOR SELECT USING (true);



CREATE POLICY "anyone_read_feedback_categories" ON "public"."feedback_categories" FOR SELECT USING (true);



CREATE POLICY "anyone_read_home_size_durations" ON "public"."home_size_durations" FOR SELECT USING (true);



CREATE POLICY "anyone_read_roles" ON "public"."roles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "anyone_read_service_categories" ON "public"."service_categories" FOR SELECT USING (true);



CREATE POLICY "anyone_read_service_types" ON "public"."service_types" FOR SELECT USING (true);



ALTER TABLE "public"."auth_identity_lookup" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."auth_lookup_rate_limit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "authenticated_read_invite_codes" ON "public"."invite_codes" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."availability" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."avatar_storage_deletions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_durations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_refunds" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "booking_refunds_select_own" ON "public"."booking_refunds" FOR SELECT TO "authenticated" USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."booking_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_timeline" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "booking_timeline_insert_by_participant" ON "public"."booking_timeline" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "booking_timeline"."booking_id") AND (("b"."customer_id" = "auth"."uid"()) OR ("b"."cleaner_id" = "auth"."uid"()))))));



CREATE POLICY "booking_timeline_select_by_participant" ON "public"."booking_timeline" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "booking_timeline"."booking_id") AND (("b"."customer_id" = "auth"."uid"()) OR ("b"."cleaner_id" = "auth"."uid"()))))));



ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bookings: insert own" ON "public"."bookings" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id") OR "public"."has_role"('admin'::"text")));



CREATE POLICY "bookings: update own" ON "public"."bookings" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id") OR "public"."has_role"('admin'::"text"))) WITH CHECK ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id") OR "public"."has_role"('admin'::"text")));



ALTER TABLE "public"."cleaner_application_drafts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_availability_exceptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_data" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cleaner_devices_cleaner_all" ON "public"."cleaner_devices" USING (("cleaner_id" = "auth"."uid"())) WITH CHECK (("cleaner_id" = "auth"."uid"()));



ALTER TABLE "public"."cleaner_leads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_schedules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_tracking" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cleaner_tracking_cleaner_insert" ON "public"."cleaner_tracking" FOR INSERT TO "authenticated" WITH CHECK ((("cleaner_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "cleaner_tracking"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"()))))));



CREATE POLICY "cleaner_tracking_cleaner_read" ON "public"."cleaner_tracking" FOR SELECT TO "authenticated" USING (("cleaner_id" = "auth"."uid"()));



CREATE POLICY "cleaner_tracking_customer_read" ON "public"."cleaner_tracking" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "cleaner_tracking"."booking_id") AND ("b"."customer_id" = "auth"."uid"())))));



CREATE POLICY "cleaner_tracking_insert_policy" ON "public"."cleaner_tracking" FOR INSERT WITH CHECK ((("auth"."uid"() = "cleaner_id") AND (EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "cleaner_tracking"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"()))))));



CREATE POLICY "cleaner_tracking_select_policy" ON "public"."cleaner_tracking" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "cleaner_tracking"."booking_id") AND (("b"."customer_id" = "auth"."uid"()) OR ("b"."cleaner_id" = "auth"."uid"()))))));



ALTER TABLE "public"."cleaner_upload_link_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cleaner_upload_links" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cleaner_upload_links_select_active_public" ON "public"."cleaner_upload_links" FOR SELECT TO "authenticated", "anon" USING ((("used_at" IS NULL) AND ("revoked_at" IS NULL) AND ("expires_at" > "now"())));



ALTER TABLE "public"."cleaner_verifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cleaners_all_own_schedules" ON "public"."cleaner_schedules" TO "authenticated" USING ((("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text"))) WITH CHECK ((("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "cleaners_manage_own_availability" ON "public"."availability" TO "authenticated" USING ((("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text"))) WITH CHECK ((("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "cleaners_select_own_verification" ON "public"."cleaner_verifications" FOR SELECT TO "authenticated" USING (("id" = "auth"."uid"()));



CREATE POLICY "cleaners_select_own_withdrawals" ON "public"."withdrawal_requests" FOR SELECT TO "authenticated" USING ((("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "cleaners_update_own_cleaner_data" ON "public"."cleaner_data" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."co_cleaner_invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "co_cleaner_invitations_select_own" ON "public"."co_cleaner_invitations" FOR SELECT USING (("auth"."uid"() = "inviter_user_id"));



CREATE POLICY "co_cleaner_invitations_update_own" ON "public"."co_cleaner_invitations" FOR UPDATE USING (("auth"."uid"() = "inviter_user_id")) WITH CHECK (("auth"."uid"() = "inviter_user_id"));



ALTER TABLE "public"."co_cleaner_relationships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "co_cleaner_relationships_select_participant" ON "public"."co_cleaner_relationships" FOR SELECT USING ((("auth"."uid"() = "lead_cleaner_id") OR ("auth"."uid"() = "co_cleaner_id")));



ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_manage_own_preferred" ON "public"."preferred_cleaners" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text"))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



ALTER TABLE "public"."deduction_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."discounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."email_signup_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."email_verifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."extra_tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."feedback" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."feedback_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_select_own" ON "public"."feedback" FOR SELECT TO "authenticated" USING ((("customer_id" = "auth"."uid"()) OR ("cleaner_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



ALTER TABLE "public"."geo_reverse_cache" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gha_staging" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."home_size_durations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inbound_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invite_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."job_offers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "job_offers_cleaner_select" ON "public"."job_offers" FOR SELECT USING (("cleaner_id" = "auth"."uid"()));



ALTER TABLE "public"."job_photo_comparisons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "job_photo_comparisons_delete" ON "public"."job_photo_comparisons" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "job_photo_comparisons"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"())))));



CREATE POLICY "job_photo_comparisons_insert" ON "public"."job_photo_comparisons" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "job_photo_comparisons"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"())))));



CREATE POLICY "job_photo_comparisons_select" ON "public"."job_photo_comparisons" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "job_photo_comparisons"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"())))));



CREATE POLICY "job_photo_comparisons_update" ON "public"."job_photo_comparisons" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "job_photo_comparisons"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "job_photo_comparisons"."booking_id") AND ("b"."cleaner_id" = "auth"."uid"())))));



ALTER TABLE "public"."jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "jobs_cleaner_select_claimed" ON "public"."jobs" FOR SELECT USING (("claimed_by" = "auth"."uid"()));



CREATE POLICY "jobs_cleaner_select_with_offer" ON "public"."jobs" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."job_offers" "o"
  WHERE (("o"."job_id" = "jobs"."id") AND ("o"."cleaner_id" = "auth"."uid"())))));



CREATE POLICY "jobs_customer_insert" ON "public"."jobs" FOR INSERT WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "jobs_customer_select" ON "public"."jobs" FOR SELECT USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."kyc_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_split_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payout_methods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payout_methods_owner_delete" ON "public"."payout_methods" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "payout_methods_owner_insert" ON "public"."payout_methods" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "payout_methods_owner_select" ON "public"."payout_methods" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "payout_methods_owner_update" ON "public"."payout_methods" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."payout_recipient_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platform_fees" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platform_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."preferred_cleaner_invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "preferred_cleaner_invitations_select_own" ON "public"."preferred_cleaner_invitations" FOR SELECT USING (("auth"."uid"() = "inviter_user_id"));



CREATE POLICY "preferred_cleaner_invitations_update_own" ON "public"."preferred_cleaner_invitations" FOR UPDATE USING (("auth"."uid"() = "inviter_user_id")) WITH CHECK (("auth"."uid"() = "inviter_user_id"));



ALTER TABLE "public"."preferred_cleaners" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pricing_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."psk_transaction" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reviewer_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reviews_insert_own_booking" ON "public"."reviews" FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "reviews"."booking_id") AND ("b"."customer_id" = "auth"."uid"())))) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "reviews_select_via_booking" ON "public"."reviews" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."id" = "reviews"."booking_id") AND (("b"."customer_id" = "auth"."uid"()) OR ("b"."cleaner_id" = "auth"."uid"()))))) OR "public"."has_role"('admin'::"text")));



ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_duration_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_duration_options_select_anon" ON "public"."service_duration_options" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."service_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."testimonials" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."timezones" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "transactions_cleaner_select" ON "public"."transactions" FOR SELECT TO "authenticated" USING (("cleaner_id" = "auth"."uid"()));



CREATE POLICY "transactions_customer_select" ON "public"."transactions" FOR SELECT TO "authenticated" USING (("customer_id" = "auth"."uid"()));



CREATE POLICY "update_own_profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



ALTER TABLE "public"."user_login_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_delete_own_cleaner_application_draft" ON "public"."cleaner_application_drafts" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "users_insert_own_cleaner_application" ON "public"."cleaner_applications" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "users_insert_own_cleaner_application_draft" ON "public"."cleaner_application_drafts" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "users_manage_own_device_tokens" ON "public"."device_tokens" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "users_select_own_cleaner_application" ON "public"."cleaner_applications" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "users_select_own_cleaner_application_draft" ON "public"."cleaner_application_drafts" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "users_select_own_notifications" ON "public"."notifications" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "users_select_own_wallet" ON "public"."wallets" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "users_update_own_cleaner_application" ON "public"."cleaner_applications" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "users_update_own_cleaner_application_draft" ON "public"."cleaner_application_drafts" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "users_update_own_notifications" ON "public"."notifications" FOR UPDATE TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text"))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."has_role"('admin'::"text")));



CREATE POLICY "users_update_own_user" ON "public"."users" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "users_viewable_via_bookings" ON "public"."users" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "id") OR (EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."cleaner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("b"."customer_id" = "users"."id")))) OR ((EXISTS ( SELECT 1
   FROM "public"."bookings" "b"
  WHERE (("b"."customer_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("b"."cleaner_id" = "users"."id")))) AND (EXISTS ( SELECT 1
   FROM "public"."cleaner_data" "cd"
  WHERE ("cd"."user_id" = "users"."id"))))));



CREATE POLICY "view_cleaner_data" ON "public"."cleaner_data" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "view_own_bookings" ON "public"."bookings" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "cleaner_id") OR "public"."has_role"('admin'::"text")));



CREATE POLICY "view_profiles" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."wallet_deductions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wallet_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wallets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."whatsapp_inbox_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."withdrawal_requests" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."bookings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."cleaner_tracking";









GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("path") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("point") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "service_role";















































































































































































































GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_co_cleaner_invite"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_preferred_cleaner_invite"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."add_cleaner_record"("p_user_id" "uuid", "p_name" "text", "p_bio" "text", "p_avatar_url" "text", "p_status" "text", "p_verified" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."add_cleaner_record"("p_user_id" "uuid", "p_name" "text", "p_bio" "text", "p_avatar_url" "text", "p_status" "text", "p_verified" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."addauth"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_and_complete_booking"("p_booking_id" "uuid", "p_rating" integer, "p_feedback" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."approve_and_complete_booking"("p_booking_id" "uuid", "p_rating" integer, "p_feedback" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_and_complete_booking"("p_booking_id" "uuid", "p_rating" integer, "p_feedback" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_cleaner_application"("p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_cleaner_application"("p_application_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text", "is_verified" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text", "is_verified" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_user_role"("target_user_id" "uuid", "target_role_id" "text", "is_verified" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."backfill_cleaner_application_approval"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."backfill_cleaner_application_approval"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."bookings_guard_payment_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."bookings_guard_payment_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bookings_guard_payment_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bookings_set_duration"() TO "anon";
GRANT ALL ON FUNCTION "public"."bookings_set_duration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bookings_set_duration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size_id" "text", "p_extra_task_ids" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size_id" "text", "p_extra_task_ids" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size_id" "text", "p_extra_task_ids" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size" "text", "p_extra_task_ids" "text"[], "p_adjustment_hours" numeric, "p_max_total_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size" "text", "p_extra_task_ids" "text"[], "p_adjustment_hours" numeric, "p_max_total_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_booking_duration"("p_home_size" "text", "p_extra_task_ids" "text"[], "p_adjustment_hours" numeric, "p_max_total_hours" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_booking_period"() TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_booking_period"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_booking_period"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_user_via_bookings"("target_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "postgres";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "anon";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."claim_job"("p_job_id" "uuid", "p_cleaner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."claim_job"("p_job_id" "uuid", "p_cleaner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_job"("p_job_id" "uuid", "p_cleaner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text", "p_is_recurring" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text", "p_is_recurring" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_booking_pricing"("p_service_id" integer, "p_duration_hours_raw" numeric, "p_scheduled_date" "date", "p_service_timezone" "text", "p_recurrence_interval" "text", "p_is_recurring" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_booking_scheduled_at_utc"() TO "anon";
GRANT ALL ON FUNCTION "public"."compute_booking_scheduled_at_utc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_booking_scheduled_at_utc"() TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_ghana_phone_variants"("raw_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."compute_ghana_phone_variants"("raw_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_ghana_phone_variants"("raw_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_co_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_preferred_cleaner_invite"("p_invitee_email" "text", "p_invitee_phone_e164" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "postgres";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "anon";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_booking_by_cleaner"("p_booking_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "postgres";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "postgres";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_single_default_platform_fee"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_single_default_platform_fee"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_single_default_platform_fee"() TO "service_role";



GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."expire_stale_pending_bookings"() TO "anon";
GRANT ALL ON FUNCTION "public"."expire_stale_pending_bookings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expire_stale_pending_bookings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fetch_cleaner_earnings"("p_user_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."fetch_cleaner_earnings"("p_user_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fetch_cleaner_earnings"("p_user_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "postgres";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "anon";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "service_role";



GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_create_wallet_for_new_cleaner"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_create_wallet_for_new_cleaner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_create_wallet_for_new_cleaner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_finalize_withdrawal"("p_transfer_reference" "text", "p_status" "public"."withdrawal_status", "p_error_msg" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_finalize_withdrawal"("p_transfer_reference" "text", "p_status" "public"."withdrawal_status", "p_error_msg" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_finalize_withdrawal"("p_transfer_reference" "text", "p_status" "public"."withdrawal_status", "p_error_msg" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_log_status_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_log_status_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_log_status_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_sync_profile_fullname"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_sync_profile_fullname"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_sync_profile_fullname"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_update_deduction_rule"("p_rule_name" "text", "p_new_rate" numeric, "p_is_fixed" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_update_deduction_rule"("p_rule_name" "text", "p_new_rate" numeric, "p_is_fixed" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_update_deduction_rule"("p_rule_name" "text", "p_new_rate" numeric, "p_is_fixed" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_active_pricing_rule"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_active_pricing_rule"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_active_pricing_rule"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_active_pricing_rule"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_available_booking_days"("p_timezone" "text", "p_duration_hours" numeric, "p_days_ahead" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_available_booking_days"("p_timezone" "text", "p_duration_hours" numeric, "p_days_ahead" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_available_booking_days"("p_timezone" "text", "p_duration_hours" numeric, "p_days_ahead" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_available_timeslots"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric, "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_available_timeslots"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric, "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_available_timeslots"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric, "p_exclude_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_available_timeslots_old"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."get_available_timeslots_old"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_available_timeslots_old"("p_booking_date" "date", "p_timezone" "text", "p_duration_hours" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_best_available_cleaners"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[], "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_best_available_cleaners"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[], "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_best_available_cleaners"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[], "p_exclude_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_best_available_cleaners_old"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_best_available_cleaners_old"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_best_available_cleaners_old"("p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer, "p_requested_services" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text", "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text", "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text", "p_exclude_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id_old"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id_old"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_availability_by_id_old"("p_cleaner_id" "uuid", "p_date" "date", "p_time" time without time zone, "p_duration" numeric, "p_timezone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_profile_v1"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_profile_v1"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_profile_v1"("target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_profile_with_reviews_and_stats"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_profile_with_reviews_and_stats"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_profile_with_reviews_and_stats"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_transaction_history"("p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_transaction_history"("p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_transaction_history"("p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaner_wallet"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaner_wallet"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaner_wallet"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cleaners_with_score"("customer_id" "uuid", "requested_services" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_cleaners_with_score"("customer_id" "uuid", "requested_services" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cleaners_with_score"("customer_id" "uuid", "requested_services" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_location_current_time"("p_timezone" "text", "p_duration_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."get_location_current_time"("p_timezone" "text", "p_duration_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_location_current_time"("p_timezone" "text", "p_duration_hours" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_wallet_balance"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_wallet_balance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_wallet_balance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_nearby_available_cleaners"("p_latitude" double precision, "p_longitude" double precision, "p_radius_meters" integer, "p_scheduled_date" "date", "p_start_time" time without time zone, "p_duration_hours" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_nearby_available_cleaners"("p_latitude" double precision, "p_longitude" double precision, "p_radius_meters" integer, "p_scheduled_date" "date", "p_start_time" time without time zone, "p_duration_hours" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_nearby_available_cleaners"("p_latitude" double precision, "p_longitude" double precision, "p_radius_meters" integer, "p_scheduled_date" "date", "p_start_time" time without time zone, "p_duration_hours" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_own_cleaner_location"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_own_cleaner_location"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_own_cleaner_location"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_payment_split_config"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_payment_split_config"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_payment_split_config"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_payout_system_logs"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_payout_system_logs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_payout_system_logs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_pending_booking_for_edit"("p_customer_id" "uuid", "p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_pending_booking_for_edit"("p_customer_id" "uuid", "p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_pending_booking_for_edit"("p_customer_id" "uuid", "p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_service_categories"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_service_categories"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_service_categories"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timezone_from_coordinates"("latitude" numeric, "longitude" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timezone_from_coordinates"("latitude" numeric, "longitude" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timezone_from_coordinates"("latitude" numeric, "longitude" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_profile_data"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_profile_stats"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_profile_stats"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_profile_stats"("p_user_id" "uuid", "p_is_cleaner" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "postgres";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "anon";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_booking_payment_status_writes"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_booking_payment_status_writes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_booking_payment_status_writes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_job_completion"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_job_completion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_job_completion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_google_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_google_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_google_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_multi_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_multi_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_multi_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("_role" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("_role" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_invite_code_usage"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_invite_code_usage"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_invite_code_usage"("p_code" "text") TO "service_role";



GRANT ALL ON TABLE "public"."psk_transaction" TO "anon";
GRANT ALL ON TABLE "public"."psk_transaction" TO "authenticated";
GRANT ALL ON TABLE "public"."psk_transaction" TO "service_role";



GRANT ALL ON FUNCTION "public"."insert_psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."insert_psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insert_psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "postgres";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "anon";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "authenticated";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin"("user_uuid" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin"("user_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"("user_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"("user_uuid" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_background_check_eligible"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_invitee_eligible"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_co_cleaner_team_member"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_platform_fee_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_platform_fee_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_platform_fee_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") TO "anon";
GRANT ALL ON FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_profile_discoverable_by_others"("p" "public"."profiles") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_profile_visible_to_viewer"("p" "public"."profiles", "viewer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."leave_co_cleaner_team"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_co_cleaner_team"() TO "anon";
GRANT ALL ON FUNCTION "public"."leave_co_cleaner_team"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."leave_co_cleaner_team"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "postgres";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "anon";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lookup_sign_in_account"("lookup_identifier" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."manage_base_durations"("action" "text", "duration_id" "text", "new_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."manage_base_durations"("action" "text", "duration_id" "text", "new_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."manage_base_durations"("action" "text", "duration_id" "text", "new_hours" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."manage_extra_tasks"("action" "text", "task_id" "text", "new_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."manage_extra_tasks"("action" "text", "task_id" "text", "new_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."manage_extra_tasks"("action" "text", "task_id" "text", "new_hours" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_cleaner_booking_milestone"("p_booking_id" "uuid", "p_milestone" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_user_accounts"("p_primary" "uuid", "p_secondary" "uuid", "p_merged_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_ghana_mobile_e164_ts"("p_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_ghana_phone_to_e164"("p_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_ghana_phone_to_e164"("p_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_ghana_phone_to_e164"("p_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_phone_for_users"("raw_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_phone_for_users"("raw_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_phone_for_users"("raw_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."phone_lookup_variants"("p_raw" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."phone_lookup_variants"("p_raw" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."phone_lookup_variants"("p_raw" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."psk_transaction"("p_booking_id" "uuid", "p_user_id" "uuid", "p_reference" "text", "p_paystack_id" bigint, "p_amount" numeric, "p_fee_amount" numeric, "p_total_captured" numeric, "p_currency" "text", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_avatar_storage_deletion"("p_object_path" "text", "p_delete_after" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_lookup_attempt"("p_scope" "text", "p_key" "text", "p_max_attempts" integer, "p_window_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_auth_identity_lookup"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_auth_identity_lookup"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_auth_identity_lookup"("target_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_device_push_token"("p_token" "text", "p_platform" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."release_cleaner_after_15min_hold"() TO "anon";
GRANT ALL ON FUNCTION "public"."release_cleaner_after_15min_hold"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_cleaner_after_15min_hold"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_co_cleaner_from_team"("p_co_cleaner_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_co_cleaner_invite"("p_invite_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_preferred_cleaner_invite"("p_invite_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."search_available_cleaners"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision, "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."search_available_cleaners"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision, "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_available_cleaners"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision, "p_exclude_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."search_available_cleaners_old"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."search_available_cleaners_old"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_available_cleaners_old"("p_lat" double precision, "p_lng" double precision, "p_date" "date", "p_time" time without time zone, "p_duration" double precision, "p_requested_services" "text"[], "p_max_distance_meters" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_booking_timezone"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_timezone"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_timezone"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_cleaner_assigned_at_for_hold"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_cleaner_assigned_at_for_hold"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_cleaner_assigned_at_for_hold"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_default_payout_method"("p_method_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "anon";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_identities"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_identities"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_identities"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_auth_identity_lookup_from_auth_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_auth_user_to_public_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_auth_user_to_public_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_auth_user_to_public_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_booking_refunds_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_booking_refunds_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_booking_refunds_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_payout_methods_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_payout_methods_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_payout_methods_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_paystack_on_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_paystack_on_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_paystack_on_approval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_booking_status"("p_booking_id" "uuid", "p_new_status" "public"."booking_status", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_booking_status"("p_booking_id" "uuid", "p_new_status" "public"."booking_status", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_booking_status"("p_booking_id" "uuid", "p_new_status" "public"."booking_status", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_cleaner_availability_exceptions_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_conversation_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_conversation_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_conversation_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_last_updated_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_last_updated_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_last_updated_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_own_cleaner_location"("p_lat" double precision, "p_lng" double precision, "p_max_distance_meters" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_platform_fees_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_platform_fees_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_platform_fees_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_booking_timeslot"("p_start_time_12h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot"("p_start_time_12h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot"("p_start_time_12h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h_debug"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h_debug"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_booking_timeslot_24h_debug"("p_start_time_24h" "text", "p_duration_hours" numeric, "p_booking_date" "date", "p_timezone" "text") TO "service_role";












GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "service_role";





















GRANT ALL ON TABLE "public"."account_merges" TO "anon";
GRANT ALL ON TABLE "public"."account_merges" TO "authenticated";
GRANT ALL ON TABLE "public"."account_merges" TO "service_role";



GRANT ALL ON TABLE "public"."auth_identity_lookup" TO "service_role";
GRANT SELECT ON TABLE "public"."auth_identity_lookup" TO "anon";
GRANT SELECT ON TABLE "public"."auth_identity_lookup" TO "authenticated";



GRANT ALL ON TABLE "public"."auth_lookup_rate_limit" TO "service_role";



GRANT ALL ON TABLE "public"."availability" TO "anon";
GRANT ALL ON TABLE "public"."availability" TO "authenticated";
GRANT ALL ON TABLE "public"."availability" TO "service_role";



GRANT ALL ON TABLE "public"."avatar_storage_deletions" TO "anon";
GRANT ALL ON TABLE "public"."avatar_storage_deletions" TO "authenticated";
GRANT ALL ON TABLE "public"."avatar_storage_deletions" TO "service_role";



GRANT ALL ON TABLE "public"."base_durations" TO "anon";
GRANT ALL ON TABLE "public"."base_durations" TO "authenticated";
GRANT ALL ON TABLE "public"."base_durations" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."booking_refunds" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."booking_refunds" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_refunds" TO "service_role";



GRANT ALL ON TABLE "public"."booking_settings" TO "anon";
GRANT ALL ON TABLE "public"."booking_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_settings" TO "service_role";



GRANT ALL ON TABLE "public"."booking_timeline" TO "anon";
GRANT ALL ON TABLE "public"."booking_timeline" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_timeline" TO "service_role";



GRANT ALL ON TABLE "public"."bookings" TO "anon";
GRANT ALL ON TABLE "public"."bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."bookings" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_application_drafts" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_application_drafts" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_application_drafts" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_applications" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_applications" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_availability_exceptions" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_availability_exceptions" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_availability_exceptions" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_data" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_data" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_data" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_devices" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_devices" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_leads" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_leads" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_leads" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_schedules" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_schedules" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_tracking" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_tracking" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_tracking" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_upload_link_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."cleaner_upload_links" TO "service_role";



GRANT SELECT("short_code") ON TABLE "public"."cleaner_upload_links" TO "anon";
GRANT SELECT("short_code") ON TABLE "public"."cleaner_upload_links" TO "authenticated";



GRANT SELECT("side") ON TABLE "public"."cleaner_upload_links" TO "anon";
GRANT SELECT("side") ON TABLE "public"."cleaner_upload_links" TO "authenticated";



GRANT SELECT("expires_at") ON TABLE "public"."cleaner_upload_links" TO "anon";
GRANT SELECT("expires_at") ON TABLE "public"."cleaner_upload_links" TO "authenticated";



GRANT SELECT("used_at") ON TABLE "public"."cleaner_upload_links" TO "anon";
GRANT SELECT("used_at") ON TABLE "public"."cleaner_upload_links" TO "authenticated";



GRANT SELECT("revoked_at") ON TABLE "public"."cleaner_upload_links" TO "anon";
GRANT SELECT("revoked_at") ON TABLE "public"."cleaner_upload_links" TO "authenticated";



GRANT ALL ON TABLE "public"."cleaner_verifications" TO "anon";
GRANT ALL ON TABLE "public"."cleaner_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."cleaner_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."co_cleaner_invitations" TO "anon";
GRANT ALL ON TABLE "public"."co_cleaner_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."co_cleaner_invitations" TO "service_role";



GRANT ALL ON TABLE "public"."co_cleaner_relationships" TO "anon";
GRANT ALL ON TABLE "public"."co_cleaner_relationships" TO "authenticated";
GRANT ALL ON TABLE "public"."co_cleaner_relationships" TO "service_role";



GRANT ALL ON TABLE "public"."conversations" TO "anon";
GRANT ALL ON TABLE "public"."conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."conversations" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."conversation_list" TO "anon";
GRANT ALL ON TABLE "public"."conversation_list" TO "authenticated";
GRANT ALL ON TABLE "public"."conversation_list" TO "service_role";



GRANT ALL ON TABLE "public"."customer_bookings_view" TO "anon";
GRANT ALL ON TABLE "public"."customer_bookings_view" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_bookings_view" TO "service_role";



GRANT ALL ON TABLE "public"."deduction_rules" TO "anon";
GRANT ALL ON TABLE "public"."deduction_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."deduction_rules" TO "service_role";



GRANT ALL ON SEQUENCE "public"."deduction_rules_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."deduction_rules_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."deduction_rules_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."device_tokens" TO "anon";
GRANT ALL ON TABLE "public"."device_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."device_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."discounts" TO "anon";
GRANT ALL ON TABLE "public"."discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."discounts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."email_signup_tokens" TO "anon";
GRANT ALL ON TABLE "public"."email_signup_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."email_signup_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."email_verifications" TO "anon";
GRANT ALL ON TABLE "public"."email_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."email_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."extra_tasks" TO "anon";
GRANT ALL ON TABLE "public"."extra_tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."extra_tasks" TO "service_role";



GRANT ALL ON TABLE "public"."feedback" TO "anon";
GRANT ALL ON TABLE "public"."feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback" TO "service_role";



GRANT ALL ON TABLE "public"."feedback_categories" TO "anon";
GRANT ALL ON TABLE "public"."feedback_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback_categories" TO "service_role";



GRANT ALL ON TABLE "public"."geo_reverse_cache" TO "anon";
GRANT ALL ON TABLE "public"."geo_reverse_cache" TO "authenticated";
GRANT ALL ON TABLE "public"."geo_reverse_cache" TO "service_role";



GRANT ALL ON TABLE "public"."gha_staging" TO "anon";
GRANT ALL ON TABLE "public"."gha_staging" TO "authenticated";
GRANT ALL ON TABLE "public"."gha_staging" TO "service_role";



GRANT ALL ON SEQUENCE "public"."gha_staging_gid_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."gha_staging_gid_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."gha_staging_gid_seq" TO "service_role";



GRANT ALL ON TABLE "public"."home_size_durations" TO "anon";
GRANT ALL ON TABLE "public"."home_size_durations" TO "authenticated";
GRANT ALL ON TABLE "public"."home_size_durations" TO "service_role";



GRANT ALL ON TABLE "public"."inbound_messages" TO "anon";
GRANT ALL ON TABLE "public"."inbound_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."inbound_messages" TO "service_role";



GRANT ALL ON SEQUENCE "public"."inbound_messages_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."inbound_messages_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."inbound_messages_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."invite_codes" TO "anon";
GRANT ALL ON TABLE "public"."invite_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."invite_codes" TO "service_role";



GRANT ALL ON TABLE "public"."job_offers" TO "anon";
GRANT ALL ON TABLE "public"."job_offers" TO "authenticated";
GRANT ALL ON TABLE "public"."job_offers" TO "service_role";



GRANT ALL ON TABLE "public"."job_photo_comparisons" TO "anon";
GRANT ALL ON TABLE "public"."job_photo_comparisons" TO "authenticated";
GRANT ALL ON TABLE "public"."job_photo_comparisons" TO "service_role";



GRANT ALL ON TABLE "public"."jobs" TO "anon";
GRANT ALL ON TABLE "public"."jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."jobs" TO "service_role";



GRANT ALL ON TABLE "public"."kyc_profiles" TO "anon";
GRANT ALL ON TABLE "public"."kyc_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."kyc_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."payment_split_config" TO "anon";
GRANT ALL ON TABLE "public"."payment_split_config" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_split_config" TO "service_role";



GRANT ALL ON TABLE "public"."payout_methods" TO "anon";
GRANT ALL ON TABLE "public"."payout_methods" TO "authenticated";
GRANT ALL ON TABLE "public"."payout_methods" TO "service_role";



GRANT ALL ON TABLE "public"."payout_recipient_audit" TO "anon";
GRANT ALL ON TABLE "public"."payout_recipient_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."payout_recipient_audit" TO "service_role";



GRANT ALL ON TABLE "public"."platform_fees" TO "anon";
GRANT ALL ON TABLE "public"."platform_fees" TO "authenticated";
GRANT ALL ON TABLE "public"."platform_fees" TO "service_role";



GRANT ALL ON TABLE "public"."platform_settings" TO "anon";
GRANT ALL ON TABLE "public"."platform_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."platform_settings" TO "service_role";



GRANT ALL ON TABLE "public"."preferred_cleaner_invitations" TO "anon";
GRANT ALL ON TABLE "public"."preferred_cleaner_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."preferred_cleaner_invitations" TO "service_role";



GRANT ALL ON TABLE "public"."preferred_cleaners" TO "anon";
GRANT ALL ON TABLE "public"."preferred_cleaners" TO "authenticated";
GRANT ALL ON TABLE "public"."preferred_cleaners" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."pricing_rules" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."pricing_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."pricing_rules" TO "service_role";



GRANT ALL ON TABLE "public"."reviewer_permissions" TO "anon";
GRANT ALL ON TABLE "public"."reviewer_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."reviewer_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."reviews" TO "anon";
GRANT ALL ON TABLE "public"."reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."reviews" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON TABLE "public"."service_categories" TO "anon";
GRANT ALL ON TABLE "public"."service_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."service_categories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."service_categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."service_categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."service_categories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."service_duration_options" TO "anon";
GRANT ALL ON TABLE "public"."service_duration_options" TO "authenticated";
GRANT ALL ON TABLE "public"."service_duration_options" TO "service_role";



GRANT ALL ON TABLE "public"."service_types" TO "anon";
GRANT ALL ON TABLE "public"."service_types" TO "authenticated";
GRANT ALL ON TABLE "public"."service_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."service_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."service_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."service_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."testimonials" TO "anon";
GRANT ALL ON TABLE "public"."testimonials" TO "authenticated";
GRANT ALL ON TABLE "public"."testimonials" TO "service_role";



GRANT ALL ON TABLE "public"."timezones" TO "anon";
GRANT ALL ON TABLE "public"."timezones" TO "authenticated";
GRANT ALL ON TABLE "public"."timezones" TO "service_role";



GRANT ALL ON SEQUENCE "public"."timezones_gid_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."timezones_gid_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."timezones_gid_seq" TO "service_role";



GRANT ALL ON TABLE "public"."transactions" TO "anon";
GRANT ALL ON TABLE "public"."transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."transactions" TO "service_role";



GRANT ALL ON TABLE "public"."user_login_sessions" TO "anon";
GRANT ALL ON TABLE "public"."user_login_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_login_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "anon";
GRANT ALL ON TABLE "public"."user_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."wallet_deductions" TO "anon";
GRANT ALL ON TABLE "public"."wallet_deductions" TO "authenticated";
GRANT ALL ON TABLE "public"."wallet_deductions" TO "service_role";



GRANT ALL ON TABLE "public"."wallet_transactions" TO "anon";
GRANT ALL ON TABLE "public"."wallet_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."wallet_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."wallets" TO "anon";
GRANT ALL ON TABLE "public"."wallets" TO "authenticated";
GRANT ALL ON TABLE "public"."wallets" TO "service_role";



GRANT ALL ON TABLE "public"."whatsapp_inbox_messages" TO "anon";
GRANT ALL ON TABLE "public"."whatsapp_inbox_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."whatsapp_inbox_messages" TO "service_role";



GRANT ALL ON TABLE "public"."withdrawal_requests" TO "anon";
GRANT ALL ON TABLE "public"."withdrawal_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."withdrawal_requests" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































